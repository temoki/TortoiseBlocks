#!/usr/bin/env ruby
# frozen_string_literal: true

# Shoots the visionOS App Store screenshots, all of them, from the simulator.
#
#   ruby Tools/visionos-shots.rb              # every shot, both locales
#   ruby Tools/visionos-shots.rb star spiral  # only the shots whose name matches
#
# Build the visionOS scheme first; this installs whatever is in DerivedData.
#
# **Why the simulator and not a headset.** A room cannot be framed the same way
# twice, and it is somebody's home. Here the picture is described entirely by
# the launch line — which drawing, how far through it, how the sheet sits, what
# language the app speaks — so a reshoot is this file plus a command, and
# tuning the framing is editing SHOTS and running it again.
#
# The one thing that is not deterministic is whether the sheet turns up at all:
# some launches open the immersive space with no attachment, and from the
# outside that looks exactly like a slow one. So the app says which it is —
# `TBReady` once the canvas has attached and the drawing is on the paper,
# `TBNotReady` if it gives up — and a shot that does not report ready is
# relaunched rather than photographed. Waiting on `EntityLoad`, which is only
# the USDZ arriving, files pictures of empty rooms.

require "fileutils"
require "json"
require "pathname"

ROOT = Pathname.new(__dir__).parent
DESTINATION = ROOT / "appstore" / "screenshots" / "visionos"
BUNDLE_ID = "space.hiraku.tortoiseblocks"

# App Store locale directory → the language the app is launched in.
LOCALES = { "en-US" => "en", "ja" => "ja" }.freeze

# The shot list. `sheet` is `side,reach,drop` in metres — how big the paper is,
# how far ahead of the eyes it lands, how far below them — and `draw` is how
# far through the program to stop, so a value under 1 catches the tortoise
# mid-line with the drawing still growing under it.
SHOTS = [
  { name: "1_star_table", sample: "star", draw: 1.0, sheet: "0.5,0.95,0.42" },
  { name: "2_spiral_drawing", sample: "spiral", draw: 0.55, sheet: "0.5,0.95,0.42" },
  { name: "3_tree_table", sample: "tree", draw: 1.0, sheet: "0.5,0.95,0.42" },
  { name: "4_square_table", sample: "square", draw: 1.0, sheet: "0.5,0.95,0.42" }
].freeze

# How long to give a launch before calling it a failure, and how many times to
# try. Three, because the flake has never needed more than a second attempt and
# a run that fails three times is telling you something else.
READY_TIMEOUT = 40
ATTEMPTS = 3

# After `TBReady`, before the shutter. The seek has landed by then; this is the
# canvas redrawing to it and the window settling.
SETTLE = 3

def simctl(*arguments)
  IO.popen(["xcrun", "simctl", *arguments], &:read)
end

def device
  json = JSON.parse(simctl("list", "devices", "booted", "-j"))
  booted = json["devices"].flat_map { |runtime, list| runtime.include?("xrOS") ? list : [] }
  abort("No booted visionOS simulator — boot one and try again.") if booted.empty?

  booted.first["udid"]
end

def app_bundle
  bundles = Pathname.glob(
    Pathname.new(Dir.home) /
      "Library/Developer/Xcode/DerivedData/TortoiseBlocks-*/Build/Products/Debug-xrsimulator/TortoiseBlocks.app"
  )
  abort("No visionOS build in DerivedData — build the scheme first.") if bundles.empty?

  bundles.max_by { |path| path.mtime }
end

# Whether this *process* reported itself ready. Filtering on the pid rather
# than the time is what keeps a previous attempt's marker from being read as
# this one's.
def ready?(udid, pid)
  deadline = Time.now + READY_TIMEOUT
  while Time.now < deadline
    log = IO.popen(
      ["xcrun", "simctl", "spawn", udid, "log", "show", "--last", "3m", "--predicate",
       "processID == #{pid} AND subsystem == \"#{BUNDLE_ID}\""], &:read
    )
    return true if log.include?("TBReady")
    return false if log.include?("TBNotReady")

    sleep(2)
  end
  false
end

def capture(udid, shot, locale, language)
  ATTEMPTS.times do |attempt|
    simctl("terminate", udid, BUNDLE_ID)
    sleep(2)
    launched = simctl(
      "launch", udid, BUNDLE_ID,
      "-TBPlace", "YES",
      "-TBSample", shot[:sample],
      "-TBDraw", shot[:draw].to_s,
      "-TBSheet", shot[:sheet],
      "-AppleLanguages", "(#{language})",
      "-AppleLocale", language == "ja" ? "ja_JP" : "en_US"
    )
    pid = launched[/:\s*(\d+)/, 1]
    next warn("  launch failed, retrying") if pid.nil?

    unless ready?(udid, pid.to_i)
      warn("  no sheet on attempt #{attempt + 1}, relaunching")
      next
    end

    sleep(SETTLE)
    target = DESTINATION / locale / "#{shot[:name]}.png"
    FileUtils.mkdir_p(target.dirname)
    simctl("io", udid, "screenshot", target.to_s)
    return target
  end
  abort("#{shot[:name]} (#{locale}) never came up with a sheet after #{ATTEMPTS} attempts")
end

wanted = ARGV.reject { |argument| argument.start_with?("-") }
shots = wanted.empty? ? SHOTS : SHOTS.select { |shot| wanted.any? { |w| shot[:name].include?(w) } }
abort("Nothing matches #{wanted.join(', ')}") if shots.empty?

udid = device
puts "device #{udid}"
simctl("install", udid, app_bundle.to_s)

LOCALES.each do |locale, language|
  shots.each do |shot|
    puts "#{locale}/#{shot[:name]}  (#{shot[:sample]}, draw #{shot[:draw]}, sheet #{shot[:sheet]})"
    puts "  → #{capture(udid, shot, locale, language).relative_path_from(ROOT)}"
  end
end

puts "\nflattening and optimising"
system("ruby", (ROOT / "Tools" / "screenshots.rb").to_s) || abort("screenshots.rb failed")
