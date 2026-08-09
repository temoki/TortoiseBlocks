# frozen_string_literal: true

# Checks appstore/ before App Store Connect ever sees it.
#
# deliver reports a too-long subtitle when it is halfway through uploading, and
# a screenshot with an alpha channel only when the submission is refused. Both
# are knowable from the files alone, so they are checked here — on every pull
# request, with no API key in sight.
#
# Plain Ruby, no gems and nothing from fastlane, for one reason: CI runs it
# straight from a checkout, and making a pull request wait for `bundle install`
# to read nine text files would cost more than the check saves. The Fastfile
# requires this file and calls it from a private lane, so a push made by hand
# passes through exactly the same code.

require "pathname"

module MetadataCheck
  LIMITS = {
    "name.txt" => 30,
    "subtitle.txt" => 30,
    "description.txt" => 4000,
    "keywords.txt" => 100,
    "promotional_text.txt" => 170,
    "release_notes.txt" => 4000
  }.freeze
  URLS = ["privacy_url.txt", "support_url.txt", "marketing_url.txt"].freeze
  REQUIRED = (LIMITS.keys + URLS).sort.freeze

  # Sizes Apple accepts for the display types this app ships. An unexpected
  # size is a mistake worth stopping on, not a shape to guess at.
  SIZES = {
    "ios" => [[2064, 2752], [2752, 2064]],                       # iPad 13-inch
    "macos" => [[1280, 800], [1440, 900], [2560, 1600], [2880, 1800]]
  }.freeze

  DEFAULT_ROOT = Pathname.new(__dir__).parent / "appstore"

  class << self
    # Every problem as [where, what], sorted. Empty means sendable.
    def problems(root: DEFAULT_ROOT)
      (text_problems(root) + screenshot_problems(root)).sort
    end

    # Prints and returns true when the tree is clean. `annotate` turns each
    # line into a GitHub Actions error.
    def report(root: DEFAULT_ROOT, annotate: false)
      found = problems(root: root)
      if found.empty?
        puts "appstore/ looks sendable."
        return true
      end

      found.each do |where, what|
        puts annotate ? "::error::#{where}: #{what}" : "  #{where}: #{what}"
      end
      puts "\n#{found.count} problem(s) in appstore/."
      false
    end

    private

    def locale_directories(parent)
      return [] unless parent.directory?

      parent.children.select { |c| c.directory? && !c.basename.to_s.start_with?(".") }.sort
    end

    def text_problems(root)
      locale_directories(root / "metadata").flat_map do |directory|
        locale = directory.basename.to_s
        REQUIRED.flat_map { |name| field_problems(directory / name, "metadata/#{locale}/#{name}") }
      end
    end

    def field_problems(path, where)
      return [[where, "missing"]] unless path.exist?

      text = path.read(encoding: "UTF-8").strip
      found = []
      found << [where, "empty"] if text.empty?
      limit = LIMITS[path.basename.to_s]
      found << [where, "#{text.length} characters, limit is #{limit}"] if limit && text.length > limit
      if URLS.include?(path.basename.to_s) && !text.start_with?("http")
        found << [where, "not an http(s) URL"]
      end
      if path.basename.to_s == "keywords.txt" && text.include?(" ")
        found << [where, "contains a space — spaces count against the 100"]
      end
      found
    end

    def screenshot_problems(root)
      SIZES.flat_map do |platform, accepted|
        locale_directories(root / "screenshots" / platform).flat_map do |directory|
          where = "screenshots/#{platform}/#{directory.basename}"
          shots = directory.children.select { |c| c.extname.casecmp(".png").zero? }.sort
          found = []
          found << [where, "no screenshots"] if shots.empty?
          found << [where, "#{shots.count} screenshots, at most 10 per locale"] if shots.count > 10
          found + shots.flat_map { |shot| shot_problems(shot, "#{where}/#{shot.basename}", accepted) }
        end
      end
    end

    def shot_problems(path, where, accepted)
      info = png_info(path)
      return [[where, "not a PNG"]] if info.nil?

      width, height, alpha = info
      found = []
      found << [where, "has an alpha channel — App Store Connect refuses one"] if alpha
      found << [where, "#{width}x#{height} is not an accepted size"] unless accepted.include?([width, height])
      found
    end

    # Width, height, and whether the file carries transparency: colour types 4
    # and 6 have an alpha channel, and a tRNS chunk is transparency by another
    # route.
    def png_info(path)
      data = path.binread
      return nil unless data[0, 8] == "\x89PNG\r\n\x1a\n".b && data[12, 4] == "IHDR"

      width, height = data[16, 8].unpack("N2")
      alpha = [4, 6].include?(data[25].ord)
      offset = 8
      while offset + 8 <= data.bytesize
        length = data[offset, 4].unpack1("N")
        kind = data[offset + 4, 4]
        alpha = true if kind == "tRNS"
        break if ["IDAT", "IEND"].include?(kind)

        offset += 12 + length
      end
      [width, height, alpha]
    end
  end
end

# Runnable on its own, which is how CI calls it: `ruby fastlane/metadata_check.rb`
if __FILE__ == $PROGRAM_NAME
  exit(MetadataCheck.report(annotate: ARGV.include?("--github")) ? 0 : 1)
end
