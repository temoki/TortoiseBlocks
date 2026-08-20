#!/usr/bin/env ruby
# frozen_string_literal: true

# Shoots the iPad App Store captures, all of them, from the simulator.
#
#   ruby Tools/ipad-shots.rb          # every shot, both locales
#   ruby Tools/ipad-shots.rb star     # only the shots whose name matches
#
# **Why a UI test and not launch arguments**, which is how the visionOS
# captures are made: rotation. `simctl` cannot turn an iPad, and driving the
# Simulator's own menu means granting keystroke permission to whatever runs
# this. `XCUIDevice` rotates in a line — and the same mechanism then presses
# play and switches panes, so the app keeps no screenshot-only code at all.
# `TortoiseBlocksUITests/ScreenshotTests.swift` is the hands; this is the
# shot list and the plumbing.
#
# Three things here are not tidiness, and each cost an hour to find.
#
# The app is **uninstalled before every run**. Opening a document that is not
# in the app's own folder imports a copy, and the name is deduplicated against
# a history that outlives deleting the files — so the title bar creeps to
# `star-9` and the capture is unusable. Uninstalling resets it.
#
# The documents are seeded into the **device's** tmp, not the app's container.
# Preparing a test run reinstalls the app, and a reinstall gives it a new data
# container, so anything seeded there beforehand is gone by the time the test
# opens it.
#
# The `TEST_RUNNER_` variables are set on **this process's environment**, not
# passed as `KEY=value` arguments to xcodebuild. Both are accepted; only one
# arrives.

require "fileutils"
require "tmpdir"
require "json"
require "pathname"

ROOT = Pathname.new(__dir__).parent
DESTINATION = ROOT / "appstore" / "screenshots" / "ios"
SOURCES = ROOT / "appstore" / "screenshot-sources"
BUNDLE_ID = "space.hiraku.tortoiseblocks"
DEVICE_NAME = "iPad Pro 13-inch (M5)"

# App Store locale directory → the language the app is launched in.
LOCALES = { "en-US" => "en", "ja" => "ja" }.freeze

# The shot list: which drawing, and which pane to end up on. The same four the
# listing has always had.
SHOTS = [
  { name: "1_star_canvas", sample: "star", pane: "canvas" },
  { name: "2_spiral_canvas", sample: "spiral", pane: "canvas" },
  { name: "3_spiral_code", sample: "spiral", pane: "code" },
  { name: "4_tree_canvas", sample: "tree", pane: "canvas" }
].freeze

def simctl(*arguments)
  IO.popen(["xcrun", "simctl", *arguments], err: %i[child out], &:read)
end

def device
  json = JSON.parse(simctl("list", "devices", "available", "-j"))
  candidates = json["devices"].flat_map do |runtime, list|
    runtime.include?("iOS") ? list.select { |d| d["name"] == DEVICE_NAME } : []
  end
  abort("No #{DEVICE_NAME} simulator.") if candidates.empty?

  booted = candidates.find { |d| d["state"] == "Booted" } || candidates.first
  udid = booted["udid"]
  if booted["state"] != "Booted"
    simctl("boot", udid)
    simctl("bootstatus", udid)
  end
  udid
end

wanted = ARGV.reject { |argument| argument.start_with?("-") }
shots = wanted.empty? ? SHOTS : SHOTS.select { |shot| wanted.any? { |w| shot[:name].include?(w) } }
abort("Nothing matches #{wanted.join(', ')}") if shots.empty?

udid = device
puts "device #{udid}"

# 9:41, the way every Apple screenshot has been since the first iPhone was
# shown. It is also the only way this is reproducible: without it the captures
# carry whatever the clock said, and a reshoot never matches the set it joins.
simctl(
  "status_bar", udid, "override",
  "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
  "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "notSupported"
)

seed = Pathname.new(Dir.home) / "Library/Developer/CoreSimulator/Devices" / udid / "data/tmp/tbshots"
FileUtils.mkdir_p(seed)
FileUtils.cp(Pathname.glob(SOURCES / "*.tortoise").map(&:to_s), seed)

# Shots grouped so that no drawing is opened twice in one run.
#
# Opening a document that is not in the app's own folder imports a copy, and
# the copy's name is deduplicated against a history that outlives deleting the
# files — so the second capture of the spiral came back titled `spiral-1`.
# Uninstalling resets that history, so the fix is to uninstall between the
# groups rather than to open the file once and photograph it twice: two
# captures of one document are two *panes*, and going back to the canvas after
# the code pane is more state to keep straight than a second launch is worth.
groups = shots.each_with_object([]) do |shot, list|
  slot = list.find { |group| group.none? { |other| other[:sample] == shot[:sample] } }
  slot ? slot << shot : list << [shot]
end

LOCALES.to_a.product(groups).each do |(locale, language), group|
  puts "#{locale}: #{group.map { |s| s[:name] }.join(', ')}"
  simctl("uninstall", udid, BUNDLE_ID)

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
    # "ja|1_star_canvas_0_<uuid>.png" — the part before the pipe is where it
    # goes, the part after is what it is called.
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
