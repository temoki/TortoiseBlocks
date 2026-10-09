# frozen_string_literal: true

# Pushes the App Store listing that lives in appstore/ (#42), through asc —
# the App Store Connect CLI (https://asccli.sh) — which replaced fastlane (#154).
#
#   ruby Tools/appstore.rb diff [ios macos visionos]   # live listing vs appstore/
#   ruby Tools/appstore.rb push [ios macos visionos]   # upload, then diff again
#
# Both need ASC_KEY_ID, ASC_ISSUER_ID and ASC_PRIVATE_KEY_PATH (a .p8 that only
# its owner can read — asc refuses a looser one). With no platform named, all
# three run. Nothing is built, signed or submitted: builds reach TestFlight from
# Xcode Cloud on a v* tag.
#
# iOS, macOS and visionOS are separate versions in App Store Connect, so each
# is its own run. iOS and macOS share appstore/metadata; visionOS is pushed from
# appstore/metadata-visionos, because a Vision Pro shopper is shown the visionOS
# description and nothing else, and the app is a different thing there — a
# viewer, with no editing in it. Name, subtitle and privacy URL are app-level
# in App Store Connect, so every run writes the same ones; metadata_check keeps
# the two directories agreeing on them.
#
# Three kinds of thing go up, each by the asc command that gets it right:
#
# - **Text** through `asc migrate import`, which reads the deliver layout the
#   directories already have. Never its screenshots: it skips a file whose
#   *name* is already live, and a reshoot keeps its names, so a new picture
#   would never replace the old one.
# - **Screenshots** a set at a time, through `asc screenshots upload --replace`,
#   with the display type named rather than inferred. That is what deliver
#   could not do: it worked display types out from pixel sizes, did not know
#   the iPhone Duo's, and its overwrite deleted every set of a locale — so the
#   Duo set went up by hand after each push. A set already matching appstore/
#   by checksum and order is left alone.
# - **App previews**, which deliver did not take at all, from appstore/previews/
#   — kept out of git, because each is megabytes. A video that is not there is
#   reported, never reshot: films are made when the maintainer asks for them
#   (Tools/film/previews.rb). Same video for both locales; the films are shot
#   in English and carry no words.
#
# A push ends with the diff, and fails unless it comes back clean: the rule is
# to trust the listing, not the log. fastlane taught that twice — a push that
# uploaded nothing and reported success, and one that uploaded everything twice.

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"
require_relative "metadata_check"

module AppStore
  APP_ID = "6798677334"
  ROOT = Pathname.new(__dir__).parent / "appstore"
  PREVIEWS = ROOT / "previews"

  # Where each screenshot goes, by directory and pixel size. A size missing here
  # stops the run: it is a mistake to stop on, not a shape to guess at — and a
  # Vision Pro capture is the same size as an Apple TV one, which is exactly
  # what guessing gets wrong. metadata_check holds the sizes Apple accepts;
  # this holds where they are filed, read back off the live listing.
  DISPLAY_TYPES = {
    "ios" => {
      [2752, 2064] => "APP_IPAD_PRO_3GEN_129", [2064, 2752] => "APP_IPAD_PRO_3GEN_129",
      # The 6.9-inch iPhone is filed under the 6.7-inch name. That is where
      # App Store Connect put these captures, and where they have to keep going.
      [1320, 2868] => "APP_IPHONE_67"
    },
    "ios_duo" => { [2853, 2007] => "APP_IPHONE_DUO", [2007, 2853] => "APP_IPHONE_DUO" },
    "macos" => {
      [2880, 1800] => "APP_DESKTOP", [2560, 1600] => "APP_DESKTOP",
      [1440, 900] => "APP_DESKTOP", [1280, 800] => "APP_DESKTOP"
    },
    "visionos" => { [3840, 2160] => "APP_APPLE_VISION_PRO" }
  }.freeze

  PLATFORMS = {
    "ios" => { connect: "IOS", metadata: "metadata", screenshots: ["ios", "ios_duo"],
               previews: { "iphone" => "APP_IPHONE_67", "ipad" => "APP_IPAD_PRO_3GEN_129" } },
    "macos" => { connect: "MAC_OS", metadata: "metadata", screenshots: ["macos"],
                 previews: { "mac" => "APP_DESKTOP" } },
    "visionos" => { connect: "VISION_OS", metadata: "metadata-visionos", screenshots: ["visionos"],
                    previews: { "vision" => "APP_APPLE_VISION_PRO" } }
  }.freeze

  # The states in which a version's metadata can still be written.
  EDITABLE = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze

  # The text fields compared, in the deliver file names both sides use.
  FIELDS = %w[name subtitle privacy_url description keywords promotional_text
              release_notes support_url marketing_url].map { |f| "#{f}.txt" }.freeze

  class Failure < StandardError; end

  module_function

  def asc(*args, json: true)
    command = ["asc", *args]
    command += ["--output", "json"] if json
    out, err, status = Open3.capture3(*command)
    raise Failure, "#{command.join(' ')}\n#{err.strip}\n#{out.strip}".strip unless status.success?

    json ? JSON.parse(out) : out
  end

  def md5(path)
    Digest::MD5.file(path.to_s).hexdigest
  end

  # The version a run is about: the one being prepared, if there is one, and
  # otherwise — for a diff only — the newest, which is what the store shows.
  def version(platform, editable:)
    versions = asc("versions", "list", "--app", APP_ID, "--platform", PLATFORMS[platform][:connect], "--paginate")["data"]
    versions = versions.sort_by { |v| v["attributes"]["createdDate"].to_s }
    open = versions.reverse.find { |v| EDITABLE.include?(v["attributes"]["appVersionState"]) }
    chosen = open || (editable ? nil : versions.last)
    raise Failure, "No editable #{platform} version — create one in App Store Connect first" if chosen.nil?

    attributes = chosen["attributes"]
    puts "#{platform} #{attributes['versionString']} (#{attributes['appVersionState']})"
    chosen["id"]
  end

  # What appstore/ says a platform's screenshots are: locale => display type =>
  # [[file name, md5]] in file-name order, which is the order they are shown.
  def local_screenshots(platform)
    sets = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }
    PLATFORMS[platform][:screenshots].each do |directory|
      Pathname.glob(ROOT / "screenshots" / directory / "*" / "*.png").sort.each do |shot|
        width, height = MetadataCheck.dimensions(shot)
        type = DISPLAY_TYPES.fetch(directory)[[width, height]]
        raise Failure, "#{shot.relative_path_from(ROOT)}: #{width}x#{height} has no display type" if type.nil?

        sets[shot.parent.basename.to_s][type] << [shot.basename.to_s, md5(shot), shot]
      end
    end
    sets
  end

  def live_screenshots(platform, version_id)
    listing = asc("screenshots", "list", "--app", APP_ID, "--version-id", version_id,
                  "--platform", PLATFORMS[platform][:connect])
    sets = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }
    listing.fetch("localizations", []).each do |localization|
      localization.fetch("sets", []).each do |set|
        type = set["set"]["attributes"]["screenshotDisplayType"]
        set.fetch("screenshots", []).each do |shot|
          sets[localization["locale"]][type] << [shot["attributes"]["fileName"], shot["attributes"]["sourceFileChecksum"].to_s]
        end
      end
    end
    sets
  end

  # The local videos, keyed by display type. Missing ones are simply absent.
  def local_previews(platform)
    PLATFORMS[platform][:previews].each_with_object({}) do |(name, type), found|
      video = PREVIEWS / "#{name}.mp4"
      found[type] = [video, md5(video)] if video.exist?
    end
  end

  # locale => display type => [md5], read from what `migrate export` wrote.
  def live_previews(export)
    sets = Hash.new { |h, k| h[k] = {} }
    Pathname.glob(export / "app_previews" / "*" / "*").select(&:directory?).each do |directory|
      checksums = Pathname.glob(directory / "*.preview.json").sort.map { |f| JSON.parse(f.read)["sourceFileChecksum"].to_s }
      sets[directory.parent.basename.to_s]["APP_#{directory.basename.to_s.upcase}"] = checksums
    end
    sets
  end

  def first_line(text)
    return "(empty)" if text.empty?

    "#{text.lines.first.strip[0, 60]} [#{text.length}]"
  end

  # Every difference between appstore/ and the live version, as printable
  # lines. Empty means the listing is what is written. `waiting` is how long to
  # give App Store Connect to work out the checksums of what was just uploaded.
  def differences(platform, version_id, waiting: 0)
    found = []
    Dir.mktmpdir("appstore-") do |tmp|
      export = Pathname.new(tmp) / "live"
      asc("migrate", "export", "--app", APP_ID, "--version-id", version_id, "--output-dir", export.to_s)

      written = ROOT / PLATFORMS[platform][:metadata]
      Pathname.glob(written / "*").select(&:directory?).sort.each do |directory|
        locale = directory.basename.to_s
        FIELDS.each do |field|
          next unless (directory / field).exist?

          local = (directory / field).read(encoding: "UTF-8").strip
          remote = export / "metadata" / locale / field
          live = remote.exist? ? remote.read(encoding: "UTF-8").strip : ""
          next if live == local

          found << "#{locale}/#{field}\n    - #{first_line(live)}\n    + #{first_line(local)}"
        end
      end

      local = local_screenshots(platform)
      live = live_screenshots(platform, version_id)
      deadline = Time.now + waiting
      while live.values.flat_map(&:values).flatten(1).any? { |_, sum| sum.empty? } && Time.now < deadline
        sleep 10
        live = live_screenshots(platform, version_id)
      end
      (local.keys | live.keys).sort.each do |locale|
        (local[locale].keys | live[locale].keys).sort.each do |type|
          want = local[locale][type].map { |name, sum, _| [name, sum] }
          have = live[locale][type]
          next if want.map(&:last) == have.map(&:last)

          found << "#{locale} #{type}: live has #{have.map(&:first).join(', ').then { |s| s.empty? ? 'nothing' : s }}" \
                   ", appstore/ has #{want.map(&:first).join(', ').then { |s| s.empty? ? 'nothing' : s }}"
        end
      end

      videos = local_previews(platform)
      previews = live_previews(export)
      PLATFORMS[platform][:previews].each do |name, type|
        unless videos.key?(type)
          puts "  previews/#{name}.mp4 is not here, so #{type} previews are not compared"
          next
        end
        locales = Pathname.glob(written / "*").select(&:directory?).map { |d| d.basename.to_s }.sort
        locales.each do |locale|
          have = previews[locale][type] || []
          next if have == [videos[type].last]

          found << "#{locale} #{type} preview: live has #{have.empty? ? 'none' : have.join(', ')}, previews/#{name}.mp4 is #{videos[type].last}"
        end
      end
    end
    found
  end

  def diff(platform)
    found = differences(platform, version(platform, editable: false))
    found.each { |line| puts "  #{line}" }
    puts(found.empty? ? "  Nothing to change." : "  #{found.count} difference(s).")
    found.empty?
  end

  def push(platform)
    version_id = version(platform, editable: true)
    config = PLATFORMS[platform]

    # The text. migrate import reads <dir>/metadata, so visionOS's own text is
    # staged under that name; screenshots and previews are handled below.
    Dir.mktmpdir("appstore-") do |tmp|
      FileUtils.cp_r((ROOT / config[:metadata]).to_s, File.join(tmp, "metadata"))
      asc("migrate", "import", "--app", APP_ID, "--version-id", version_id, "--fastlane-dir", tmp,
          "--skip-screenshots", "--skip-previews", "--skip-app-clip", "--confirm")
      puts "  text: sent"
    end

    local = local_screenshots(platform)
    live = live_screenshots(platform, version_id)
    local.keys.sort.each do |locale|
      local[locale].keys.sort.each do |type|
        files = local[locale][type]
        if files.map { |_, sum, _| sum } == live[locale][type].map(&:last)
          puts "  #{locale} #{type}: unchanged"
          next
        end

        # One set per call, from a directory holding only that set's files,
        # so --replace empties exactly the set it is given and nothing else.
        Dir.mktmpdir("appstore-shots-") do |tmp|
          files.each { |name, _, path| FileUtils.cp(path.to_s, File.join(tmp, name)) }
          asc("screenshots", "upload", "--app", APP_ID, "--version-id", version_id,
              "--platform", config[:connect], "--locale", locale, "--path", tmp,
              "--device-type", type.delete_prefix("APP_"), "--replace", "--confirm")
        end
        puts "  #{locale} #{type}: #{files.count} screenshot(s) sent"
      end
    end

    videos = local_previews(platform)
    unless videos.empty?
      localizations = asc("localizations", "list", "--version", version_id)["data"]
                      .to_h { |l| [l["attributes"]["locale"], l["id"]] }
      live_videos = Dir.mktmpdir("appstore-") do |tmp|
        asc("migrate", "export", "--app", APP_ID, "--version-id", version_id, "--output-dir", tmp)
        live_previews(Pathname.new(tmp))
      end
      local.keys.sort.each do |locale|
        videos.each do |type, (video, sum)|
          if live_videos[locale][type] == [sum]
            puts "  #{locale} #{type} preview: unchanged"
            next
          end

          asc("video-previews", "upload", "--version-localization", localizations.fetch(locale),
              "--path", video.to_s, "--device-type", type.delete_prefix("APP_"), "--replace", "--confirm")
          puts "  #{locale} #{type} preview: #{video.basename} sent"
        end
      end
    end

    found = differences(platform, version_id, waiting: 300)
    return true if found.empty?

    found.each { |line| puts "  #{line}" }
    raise Failure, "#{platform}: the listing still differs from appstore/ after the push"
  end
end

if __FILE__ == $PROGRAM_NAME
  command, *platforms = ARGV
  platforms = AppStore::PLATFORMS.keys if platforms.empty?
  unknown = platforms - AppStore::PLATFORMS.keys
  unless %w[diff push].include?(command) && unknown.empty?
    warn "usage: ruby Tools/appstore.rb diff|push [#{AppStore::PLATFORMS.keys.join(' ')}]"
    exit 2
  end

  begin
    if command == "push"
      abort "appstore/ has problems — see above." unless MetadataCheck.report
    end
    clean = platforms.map { |platform| AppStore.public_send(command, platform) }
    exit(clean.all? ? 0 : 1)
  rescue AppStore::Failure => e
    abort e.message
  end
end
