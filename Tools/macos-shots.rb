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

# How far a corner's wedge can reach into a capture, in pixels. The wedge is
# about 54px square on a 2× capture; the box only has to hold it.
CORNER = 128

# More of the box than this gone means the fill ran into the window itself.
# A real wedge is under 5% of it.
LEAKED = 0.25

# The window with its rounded corners knocked out.
#
# `XCUIElement.screenshot()` hands back the window's *bounding box*, fully
# opaque, and outside the rounded corners is **whatever is on screen behind the
# window** — near-black on a dark desktop, which is what this was first written
# against, and composited as-is the window wears four black wedges. The corners
# are flood-filled rather than masked with a drawn radius: the shape is macOS's
# own continuous curve, not a circle.
#
# A flood fill only finds the wedge when the wedge differs from the window,
# though. With a light window behind a corner the fill runs straight through
# the white canvas and takes the whole background with it — the plate shows
# through every white pixel and nothing fails. So each corner is filled inside
# its own box, which bounds the damage, and a corner whose fill spread through
# the box borrows the other corner on its edge, mirrored: a window is symmetric
# left to right, while its top and bottom wedges differ by a few rows. Both
# corners of an edge light stops the run, because there is nothing to copy.
def round_corners(source, target)
  width, height = size(source)
  workspace = Pathname.new(Dir.mktmpdir)
  origins = {
    top_left: [0, 0], top_right: [width - CORNER, 0],
    bottom_left: [0, height - CORNER], bottom_right: [width - CORNER, height - CORNER]
  }
  partners = { top_left: :top_right, top_right: :top_left,
               bottom_left: :bottom_right, bottom_right: :bottom_left }

  masks = origins.to_h do |corner, (x, y)|
    mask = workspace / "#{corner}-mask.png"
    seed = "#{x.zero? ? 0 : CORNER - 1},#{y.zero? ? 0 : CORNER - 1}"
    magick(source.to_s, "-crop", "#{CORNER}x#{CORNER}+#{x}+#{y}", "+repage",
           "-alpha", "set", "-fuzz", "12%", "-fill", "none", "-draw", "color #{seed} floodfill",
           "-alpha", "extract", mask.to_s)
    gone = 1 - IO.popen(["magick", "identify", "-format", "%[fx:mean]", mask.to_s], err: File::NULL, &:read).to_f
    [corner, { path: mask, clean: gone < LEAKED }]
  end

  layers = origins.map do |corner, (x, y)|
    mask = masks[corner]
    unless mask[:clean]
      partner = masks[partners[corner]]
      unless partner[:clean]
        abort("#{source}: both #{corner.to_s.split('_').first} corners have something light " \
              "behind them, so neither shows the window's shape — put something dark behind " \
              "the window and shoot again")
      end
      borrowed = workspace / "#{corner}-borrowed.png"
      magick(partner[:path].to_s, "-flop", borrowed.to_s)
      mask = { path: borrowed }
    end
    layer = workspace / "#{corner}.png"
    magick(source.to_s, "-crop", "#{CORNER}x#{CORNER}+#{x}+#{y}", "+repage", "-alpha", "set",
           mask[:path].to_s, "-compose", "CopyOpacity", "-composite", layer.to_s)
    [layer, x, y]
  end

  magick(source.to_s, "-alpha", "set", "-compose", "Copy",
         *layers.flat_map { |layer, x, y| [layer.to_s, "-geometry", "+#{x}+#{y}", "-composite"] },
         target.to_s)
  FileUtils.rm_rf(workspace)
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
