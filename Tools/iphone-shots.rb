#!/usr/bin/env ruby
# frozen_string_literal: true

# Shoots the iPhone App Store captures, from the simulator.
#
#   ruby Tools/iphone-shots.rb          # every shot, both locales
#   ruby Tools/iphone-shots.rb palette  # only the shots whose name matches
#
# **They go in the same directory as the iPad's** (#114). App Store Connect has
# one iOS version carrying both display types, `deliver` takes one screenshots
# directory per platform, and it tells an iPhone capture from an iPad one by
# its dimensions — so `appstore/screenshots/ios/<locale>/` holds both sets, and
# the leading number in a filename orders each set within its own display type.
# The `iphone` in these names is for the person reading the directory.
#
# **The device is an iPhone 17 Pro Max**, because 1320x2868 is one of the two
# sizes Apple accepts for the 6.9-inch display. The iPhone 17 is 1206x2622,
# which is a perfectly good picture that App Store Connect refuses.
#
# **The pictures are not the iPad's four.** There is nowhere on a phone to show
# palette, program and canvas at once, so the set shows the screens instead:
# the program with its bottom bar, the canvas sheet the ▶ raises, the code
# sheet, and the palette sheet over a program. `ScreenshotTests.swift` knows
# how to reach each of them; the panes `blocks` and `palette` exist only here.
#
# **The documents go in the app's own folder, and the test taps them.** This
# is the one real difference from the iPad rig, and it is forced: a phone
# cannot be handed a document by URL at all (see `openFromBrowser` in
# `ScreenshotTests`). So the app is installed here, before the tests, its
# container is seeded, and nothing uninstalls afterwards — an uninstall would
# take the documents with it. Opening in place also means no import, so the
# name-deduplication the iPad rig groups its shots around (`spiral-1` in a
# title bar) cannot happen, and every shot for a locale goes in one run.
#
# Everything else is the iPad rig's, for the same reasons it is there:
# `ScreenshotTests.swift` does the pressing, the status bar is pinned to 9:41,
# the simulator's system language is switched per locale (the status bar's date
# is the system's, not the app's), and `TEST_RUNNER_*` has to be on
# xcodebuild's own environment rather than passed as arguments. Rotation is the
# one thing this does not do: the phone is portrait only (#113).

require "fileutils"
require "json"
require "pathname"
require "tmpdir"

ROOT = Pathname.new(__dir__).parent
DESTINATION = ROOT / "appstore" / "screenshots" / "ios"
SOURCES = ROOT / "appstore" / "screenshot-sources"
BUNDLE_ID = "space.hiraku.tortoiseblocks"
DEVICE_NAME = "iPhone 17 Pro Max"

# App Store locale directory → the language the app is launched in.
LOCALES = { "en-US" => "en", "ja" => "ja" }.freeze

# App Store locale directory → the simulator's system language, which is what
# the status bar's date is written in.
SYSTEM_LANGUAGES = {
  "en-US" => { languages: %w[en-US], locale: "en_US" },
  "ja" => { languages: %w[ja-JP], locale: "ja_JP" }
}.freeze

# The shot list: which drawing, and which screen to end up on. One picture per
# screen the phone has, in the order a child meets them.
SHOTS = [
  { name: "1_iphone_star_blocks", sample: "star", pane: "blocks" },
  { name: "2_iphone_star_canvas", sample: "star", pane: "canvas" },
  { name: "3_iphone_spiral_code", sample: "spiral", pane: "code" },
  { name: "4_iphone_tree_palette", sample: "tree", pane: "palette" }
].freeze

def simctl(*arguments)
  IO.popen(["xcrun", "simctl", *arguments], err: %i[child out], &:read)
end

# The newest iOS runtime that has this device, and **the runtime is not a
# detail**: on iOS 26.5 `XCUIDevice.system.open` does not open a document at
# all. It imports it — the file lands in the app's Inbox and the browser stays
# up, or a "save as" panel appears — and every capture is then of the launch
# screen. Opening a seeded document is how both this rig and the iPad's reach
# a drawing, so a device on the wrong runtime silently shoots nothing usable.
# iOS 27.0 opens it. Runtimes sort as strings here because they are
# "com.apple.CoreSimulator.SimRuntime.iOS-27-0", which orders correctly for as
# long as the numbers stay one digit; the check below is what actually
# protects the run.
def device
  json = JSON.parse(simctl("list", "devices", "available", "-j"))
  candidates = json["devices"].flat_map do |runtime, list|
    runtime.include?("iOS") ? list.select { |d| d["name"] == DEVICE_NAME }.map { |d| [runtime, d] } : []
  end
  abort("No #{DEVICE_NAME} simulator.") if candidates.empty?

  runtime, chosen = candidates.max_by { |r, _| r }
  version = runtime[/iOS-(\d+)-(\d+)/, 0].to_s.sub("iOS-", "").tr("-", ".")
  abort("#{DEVICE_NAME} is only on iOS #{version}; 27.0 or newer opens documents, 26.5 does not.") if version < "27"

  udid = chosen["udid"]
  if chosen["state"] != "Booted"
    simctl("boot", udid)
    simctl("bootstatus", udid)
  end
  puts "runtime iOS #{version}"
  udid
end

def system_language(udid)
  languages = simctl("spawn", udid, "defaults", "read", "-g",
                     "AppleLanguages").scan(/[A-Za-z]{2,3}(?:-[A-Za-z0-9]+)*/)
  { languages: languages, locale: simctl("spawn", udid, "defaults", "read", "-g", "AppleLocale").strip }
end

def write_system_language(udid, language)
  simctl("spawn", udid, "defaults", "write", "-g", "AppleLanguages", "-array", *language[:languages])
  simctl("spawn", udid, "defaults", "write", "-g", "AppleLocale", language[:locale])
end

# 9:41, the way every Apple screenshot has been since the first iPhone was
# shown. It is also the only way this is reproducible: without it the captures
# carry whatever the clock said, and a reshoot never matches the set it joins.
def override_status_bar(udid)
  simctl(
    "status_bar", udid, "override",
    "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
    "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "notSupported"
  )
end

# A language takes effect only after a restart, and a restart can take the
# status bar override and the seeded documents with it, so both are put back.
def restart(udid)
  simctl("shutdown", udid)
  simctl("boot", udid)
  simctl("bootstatus", udid)
end

wanted = ARGV.reject { |argument| argument.start_with?("-") }
shots = wanted.empty? ? SHOTS : SHOTS.select { |shot| wanted.any? { |w| shot[:name].include?(w) } }
abort("Nothing matches #{wanted.join(', ')}") if shots.empty?

udid = device
puts "device #{udid}"

# Whatever the simulator was set to goes back, however the run ends — a device
# left in English is a surprise the next time somebody opens it.
original_language = system_language(udid)
at_exit { write_system_language(udid, original_language) }

# The app goes on now, so that its container exists to seed. `xcodebuild test`
# installs over this rather than replacing it, which is what keeps the
# documents there.
product = JSON.parse(
  `xcodebuild -project "#{ROOT}/TortoiseBlocks.xcodeproj" -scheme TortoiseBlocks \
     -destination "id=#{udid}" -showBuildSettings -json 2>/dev/null`
)
settings = product.first["buildSettings"]
app = Pathname.new(settings["BUILT_PRODUCTS_DIR"]) / settings["FULL_PRODUCT_NAME"]
abort("No built app at #{app} — build the scheme first.") unless app.exist?
simctl("install", udid, app.to_s)

seed = Pathname.new(simctl("get_app_container", udid, BUNDLE_ID, "data").strip) / "Documents"

current_language = nil
LOCALES.to_a.product([shots]).each do |(locale, language), group|
  puts "#{locale}: #{group.map { |s| s[:name] }.join(', ')}"

  unless current_language == locale
    wanted_language = SYSTEM_LANGUAGES.fetch(locale)
    unless system_language(udid) == wanted_language
      puts "  switching the simulator to #{wanted_language[:locale]} and restarting it"
      write_system_language(udid, wanted_language)
      restart(udid)
    end
    override_status_bar(udid)
    # The container survives the language restart, but is re-seeded anyway:
    # a run that ends mid-way can leave a document renamed or deleted.
    # **Light, said outright.** The captures this set joins are light, and a
    # simulator's appearance is whatever the device was left in — a freshly
    # created one on a new runtime came up dark, which is a perfectly
    # well-made capture of the wrong thing.
    simctl("ui", udid, "appearance", "light")
    FileUtils.mkdir_p(seed)
    FileUtils.cp(Pathname.glob(SOURCES / "*.tortoise").map(&:to_s), seed)
    current_language = locale
  end

  workspace = Pathname.new(Dir.mktmpdir)
  result = workspace / "shots.xcresult"

  environment = {
    "TEST_RUNNER_TB_DOCUMENTS" => seed.to_s,
    "TEST_RUNNER_TB_SHOTS" => group.map { |s| "#{s[:name]}:#{s[:sample]}:#{s[:pane]}" }.join(","),
    "TEST_RUNNER_TB_LOCALE" => locale,
    "TEST_RUNNER_TB_LANGUAGE" => language
  }
  command = [
    "xcodebuild", "test",
    "-project", (ROOT / "TortoiseBlocks.xcodeproj").to_s,
    "-scheme", "TortoiseBlocks",
    "-destination", "id=#{udid}",
    "-only-testing:TortoiseBlocksUITests/ScreenshotTests",
    "-parallel-testing-enabled", "NO",
    "-resultBundlePath", result.to_s,
    "-quiet"
  ]
  abort("#{locale}: the test run failed") unless system(environment, *command)

  exported = Pathname.new(Dir.mktmpdir)
  unless system("xcrun", "xcresulttool", "export", "attachments",
                "--path", result.to_s, "--output-path", exported.to_s,
                out: File::NULL, err: File::NULL)
    abort("#{locale}: could not export the captures")
  end

  manifest = JSON.parse((exported / "manifest.json").read)
  filed = manifest.flat_map { |test| test["attachments"] }.filter_map do |attachment|
    # "ja|1_iphone_star_blocks_0_<uuid>.png" — the part before the pipe is
    # where it goes, the part after is what it is called.
    where, rest = attachment["suggestedHumanReadableName"].split("|", 2)
    next if rest.nil?

    name = rest.sub(/_\d+_[0-9A-F-]+\.png\z/, "")
    target = DESTINATION / where / "#{name}.png"
    FileUtils.mkdir_p(target.dirname)
    FileUtils.cp(exported / attachment["exportedFileName"], target)
    puts "  → #{target.relative_path_from(ROOT)}"
    target
  end
  abort("#{locale}: no captures came back") if filed.empty?

  FileUtils.rm_rf(exported)
  FileUtils.rm_rf(workspace)
end

simctl("status_bar", udid, "clear")

puts "\nflattening and optimising"
system("ruby", (ROOT / "Tools" / "screenshots.rb").to_s) || abort("screenshots.rb failed")
