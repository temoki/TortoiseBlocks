#!/usr/bin/env ruby
# frozen_string_literal: true

# Shoots the macOS App Store captures: the app's window, composited onto a
# prepared plate.
#
#   ruby Tools/macos-shots.rb          # every shot, both locales
#   ruby Tools/macos-shots.rb star     # only the shots whose name matches
#
# **The capture is the window alone**, taken by `XCUIElement.screenshot()` in
# `TortoiseBlocksUITests/ScreenshotTests.swift`. Everything around it — the
# desktop and the menu bar — comes from `appstore/screenshot-sources/
# macos-plate-{en,ja}.png`, made once per language. That is what keeps the
# capture independent of the machine: whatever wallpaper, menu extras or clock
# the Mac happens to have never reach the picture.
#
# The plates carry **no shadow**. It is generated here instead, so the window
# can change size or move without the plates being remade — which matters,
# because the previous set had one capture whose window sat 14px off the other
# seven and a baked shadow would have meant redrawing the artwork to fix it.
#
# macOS UI testing needs Xcode to hold the **Accessibility** permission
# (System Settings ▸ Privacy & Security ▸ Accessibility). Without it every run
# fails with "Timed out while enabling automation mode", which says nothing
# about permissions at all.

require "fileutils"
require "json"
require "pathname"
require "tmpdir"

ROOT = Pathname.new(__dir__).parent
DESTINATION = ROOT / "appstore" / "screenshots" / "macos"
SOURCES = ROOT / "appstore" / "screenshot-sources"
BUNDLE_ID = "space.hiraku.tortoiseblocks"

LOCALES = { "en-US" => "en", "ja" => "ja" }.freeze

SHOTS = [
  { name: "1_star_canvas", sample: "star", pane: "canvas" },
  { name: "2_spiral_canvas", sample: "spiral", pane: "canvas" },
  { name: "3_spiral_code", sample: "spiral", pane: "code" },
  { name: "4_tree_canvas", sample: "tree", pane: "canvas" }
].freeze

# The menu bar the plates were drawn with, in pixels. Everything else about the
# placement is computed, so a differently sized window still lands centred.
MENU_BAR = 48

# opacity × blur, then the drop. Judged against the previous hand-made set.
SHADOW = "55x30+0+22"

def magick(*arguments)
  return if system("magick", *arguments, err: File::NULL)

  abort("magick failed: #{arguments.join(' ')}")
end

def size(path)
  IO.popen(["magick", "identify", "-format", "%w %h", path.to_s], &:read).split.map(&:to_i)
end

# The window with its rounded corners knocked out.
#
# `XCUIElement.screenshot()` hands back the window's *bounding box*, fully
# opaque, with the corners filled near-black — composite that and the window
# gets four black wedges. The corners are flood-filled rather than masked with
# a drawn radius: the shape is macOS's own continuous curve, not a circle, and
# the wedges are the only near-black regions touching the corners of the image.
def round_corners(source, target)
  width, height = size(source)
  magick(
    source.to_s, "-alpha", "set", "-fuzz", "12%",
    "-fill", "none", "-draw", "color 0,0 floodfill",
    "-fill", "none", "-draw", "color #{width - 1},0 floodfill",
    "-fill", "none", "-draw", "color 0,#{height - 1} floodfill",
    "-fill", "none", "-draw", "color #{width - 1},#{height - 1} floodfill",
    target.to_s
  )
end

def compose(window, plate, target)
  workspace = Pathname.new(Dir.mktmpdir)
  rounded = workspace / "window.png"
  shadow = workspace / "shadow.png"
  round_corners(window, rounded)
  magick(rounded.to_s, "-background", "black", "-shadow", SHADOW, shadow.to_s)

  plate_width, plate_height = size(plate)
  window_width, window_height = size(rounded)
  x = (plate_width - window_width) / 2
  y = MENU_BAR + (plate_height - MENU_BAR - window_height) / 2

  # `-shadow` grows the canvas and records how far by in the page offset, so
  # the shadow lands under the window rather than beside it.
  offset = IO.popen(
    ["magick", "identify", "-format", "%[fx:page.x] %[fx:page.y]", shadow.to_s], &:read
  ).split.map(&:to_i)

  magick(
    plate.to_s,
    shadow.to_s, "-gravity", "NorthWest", "-geometry", "+#{x + offset[0]}+#{y + offset[1]}",
    "-composite",
    rounded.to_s, "-gravity", "NorthWest", "-geometry", "+#{x}+#{y}", "-composite",
    target.to_s
  )
  FileUtils.rm_rf(workspace)
end

wanted = ARGV.reject { |argument| argument.start_with?("-") }
shots = wanted.empty? ? SHOTS : SHOTS.select { |shot| wanted.any? { |w| shot[:name].include?(w) } }
abort("Nothing matches #{wanted.join(', ')}") if shots.empty?

seed = Pathname.new(Dir.mktmpdir)
FileUtils.cp(Pathname.glob(SOURCES / "*.tortoise").map(&:to_s), seed)

LOCALES.each do |locale, language|
  plate = SOURCES / "macos-plate-#{language}.png"
  abort("Missing #{plate.relative_path_from(ROOT)}") unless plate.exist?

  puts "#{locale}: #{shots.map { |s| s[:name] }.join(', ')}"

  # Every capture has to be the same size, and macOS restores a window's saved
  # frame in preference to the app's `defaultSize`. Throwing the saved state
  # away is what makes 1280×800pt — and so 2560×1600px — reproducible.
  FileUtils.rm_rf(Pathname.new(Dir.home) / "Library/Saved Application State/#{BUNDLE_ID}.savedState")
  system("defaults", "delete", BUNDLE_ID, out: File::NULL, err: File::NULL)

  workspace = Pathname.new(Dir.mktmpdir)
  result = workspace / "shots.xcresult"
  environment = {
    "TEST_RUNNER_TB_DOCUMENTS" => seed.to_s,
    "TEST_RUNNER_TB_SHOTS" => shots.map { |s| "#{s[:name]}:#{s[:sample]}:#{s[:pane]}" }.join(","),
    "TEST_RUNNER_TB_LOCALE" => locale,
    "TEST_RUNNER_TB_LANGUAGE" => language
  }
  command = [
    "xcodebuild", "test",
    "-project", (ROOT / "TortoiseBlocks.xcodeproj").to_s,
    "-scheme", "TortoiseBlocks",
    "-destination", "platform=macOS",
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
    where, rest = attachment["suggestedHumanReadableName"].split("|", 2)
    next if rest.nil?

    name = rest.sub(/_\d+_[0-9A-F-]+\.png\z/, "")
    target = DESTINATION / where / "#{name}.png"
    FileUtils.mkdir_p(target.dirname)
    compose(exported / attachment["exportedFileName"], plate, target)
    puts "  → #{target.relative_path_from(ROOT)}"
    target
  end
  abort("#{locale}: no captures came back") if filed.empty?

  FileUtils.rm_rf(exported)
  FileUtils.rm_rf(workspace)
end

FileUtils.rm_rf(seed)

puts "\nflattening and optimising"
system("ruby", (ROOT / "Tools" / "screenshots.rb").to_s) || abort("screenshots.rb failed")
