#!/usr/bin/env ruby
# frozen_string_literal: true

# Makes the App Store app previews: fifteen-odd seconds per device, English,
# no captions, silent — the music goes on by hand, as it does for the teaser.
#
#   ruby Tools/film/previews.rb              # every device, record and compose
#   ruby Tools/film/previews.rb ipad         # only the ones named
#   ruby Tools/film/previews.rb --compose    # compose the last recordings again
#
# The films land in the work directory printed at the end. They are not
# committed — each is megabytes, and the listing takes them by hand: fastlane's
# deliver uploads screenshots but not previews.
#
# **Apple's rules are what shape these**, and they are stricter than the
# teaser's (developer.apple.com/app-store/app-previews/ and the preview
# specifications in App Store Connect's help):
#
# - The screen as captured: no zooming into the UI, so there is no camera,
#   and nothing that is not the device — no backdrop, no cards. Graphics that
#   show where to touch are allowed, so the touches are drawn as in the
#   teaser.
# - 15 to 30 seconds. A cut that comes out short holds its last frame.
# - One exact size per device class, 30fps at most, H.264 High, and an audio
#   track, which is required even when it is silence.
#
# `TortoiseBlocksUITests/AppPreviewTests.swift` holds the scripts, one test per
# device. Each starts from a document already holding most of its program,
# written here in PREVIEWS: fifteen seconds is too short to build one from
# nothing and still watch it draw.

require "time"
require "tmpdir"
require_relative "film"

WORK = Pathname.new(Dir.tmpdir) / "tortoise-previews"
FPS = Film::FPS
SHORTEST = 15.5
LONGEST = 30.0

# Blocks in the frozen wire format (`BlockCodableTests` has every kind).
def forward(steps)
  { "forward" => { "literal" => steps } }
end

def turn_right(degrees)
  { "turnRight" => { "literal" => degrees } }
end

def pen_width(width)
  { "penWidth" => { "literal" => width } }
end

PREVIEWS = {
  # 4:3, which only the 13-inch iPad is; the 11-inch would have to be cropped.
  "ipad" => {
    device: "iPad Pro 13-inch (M5)", test: "AppPreviewTests/testIPad",
    landscape: true, size: [1600, 1200],
    documents: {
      "My Drawing" => [
        pen_width(6),
        { "repeat" => { "count" => { "literal" => 5 }, "body" => [forward(150), turn_right(90)] } }
      ]
    }
  },
  # 886×1920 is a hair taller than the 6.9-inch screen, so a few rows go.
  "iphone" => {
    device: "iPhone 17 Pro Max", test: "AppPreviewTests/testIPhone",
    landscape: false, size: [886, 1920], phone: true,
    documents: {
      "My Drawing" => [
        pen_width(6), { "penColor" => "orange" },
        { "repeat" => { "count" => { "literal" => 5 }, "body" => [] } }
      ]
    }
  },
  # The Mac's own window, recorded where it runs: this Mac, not a simulator.
  # The test drives the real pointer, so this one wants the machine left alone
  # for the three minutes it takes, with the screen unlocked.
  "mac" => {
    mac: true, test: "MacPreviewTests/testMac", size: [1920, 1080],
    plate: "appstore/screenshot-sources/macos-plate-en.png",
    documents: {
      "My Drawing" => [
        pen_width(6),
        { "repeat" => { "count" => { "literal" => 5 }, "body" => [forward(150), turn_right(90)] } }
      ]
    }
  },
  # No script: a simulator takes no input, so the preview is the viewer doing
  # what it is for — the star being drawn on the table, with the blocks and the
  # code in their windows. The launch arguments are the screenshot rig's.
  "vision" => {
    device: "Apple Vision Pro", os: "xrOS", size: [3840, 2160],
    sample: "star", sheet: "0.7,1.2,0.38",
    # 0.5 / level seconds a step: the star's 74 steps take 14.2s at 2.6, and
    # the legs have time to be seen changing feet.
    speed: 2.6, length: 16.5,
    # How long after the sheet is up the drawing starts: time for the
    # recorder, which may not be running while the app launches.
    wait: 6
  }
}.freeze

def run(*command)
  Film.run(*command)
end

# ---------------------------------------------------------------------------
# Vision Pro: launched, not scripted.

# The fraction of the frame that is strongly saturated: the windows put a
# palette of pastels in the picture and an empty room has none (the
# screenshot rig's measure; a real capture is 0.07–0.09, a room 0.01–0.02).
def ink(image)
  IO.popen(["magick", image.to_s, "-colorspace", "HSL", "-channel", "G", "-separate", "+channel",
            "-threshold", "40%", "-format", "%[fx:mean]", "info:"], &:read).to_f
end

# When this launch logged `marker`, by the log's own clock, or nil if it said
# `TBNotReady` instead or nothing at all in time.
def logged_at(udid, pid, marker, timeout: 40)
  deadline = Time.now + timeout
  while Time.now < deadline
    lines = IO.popen(["xcrun", "simctl", "spawn", udid, "log", "show", "--last", "3m", "--style", "ndjson",
                      "--predicate", "processID == #{pid} AND subsystem == \"#{Film::BUNDLE_ID}\""], &:read)
    lines.each_line do |line|
      entry = JSON.parse(line) rescue next
      message = entry["eventMessage"].to_s
      return nil if message.include?("TBNotReady")
      return Time.strptime(entry["timestamp"], "%Y-%m-%d %H:%M:%S.%N%z").to_f if message.include?(marker)
    end
    sleep(0.5)
  end
  nil
end

# **Recording starts after the sheet is up, never before the launch.** With
# `simctl io recordVideo` running while the app launches, the immersive space
# does not open at all — the windows come up and the app reports `TBNotReady`,
# every time, restarted simulator or not. So the app is told to wait
# (`-TBPlay <seconds>`) before it plays: the sheet comes up, the recorder
# starts, and the drawing begins in front of it at `TBPlaying`.
def record_vision(profile, raw)
  udid = Film.device(profile[:device], os: profile[:os], minimum: "26")
  run("xcodebuild", "-project", (Film::ROOT / "TortoiseBlocks.xcodeproj").to_s, "-scheme", "TortoiseBlocks",
      "-destination", "id=#{udid}", "-quiet", "build")
  settings = JSON.parse(`xcodebuild -project "#{Film::ROOT}/TortoiseBlocks.xcodeproj" -scheme TortoiseBlocks \
                         -destination "id=#{udid}" -showBuildSettings -json 2>/dev/null`).first["buildSettings"]
  app = Pathname.new(settings["BUILT_PRODUCTS_DIR"]) / settings["FULL_PRODUCT_NAME"]

  FileUtils.rm_rf(raw)
  FileUtils.mkdir_p(raw)
  3.times do |attempt|
    # Reinstalled every time: visionOS restores an app's windows, and a launch
    # that inherits the last one's opens a second set on top.
    Film.simctl("terminate", udid, Film::BUNDLE_ID)
    Film.simctl("uninstall", udid, Film::BUNDLE_ID)
    Film.simctl("install", udid, app.to_s)
    sleep(2)
    launched = Film.simctl("launch", udid, Film::BUNDLE_ID,
                           "-TBPlace", "YES", "-TBSample", profile[:sample], "-TBDraw", "0",
                           "-TBPlay", profile[:wait].to_s, "-TBSpeed", profile[:speed].to_s,
                           "-TBSheet", profile[:sheet], "-AppleLanguages", "(en)", "-AppleLocale", "en_US")
    pid = launched[/:\s*(\d+)/, 1]
    unless pid && logged_at(udid, pid.to_i, "TBReady")
      warn("  no sheet on attempt #{attempt + 1}, relaunching")
      next
    end

    recorder, started = Film.start_recording(udid, raw / "raw.mov")
    playing = logged_at(udid, pid.to_i, "TBPlaying", timeout: profile[:wait] + 10)
    sleep(profile[:length] + 1) if playing
    Film.stop_recording(recorder)
    Film.simctl("terminate", udid, Film::BUNDLE_ID)
    unless playing && playing > started
      warn("  the drawing started before the recorder on attempt #{attempt + 1}, relaunching")
      next
    end

    (raw / "recording.json").write(JSON.generate({ "started" => started, "playing" => playing }))
    probe = raw / "probe.png"
    Film.run("ffmpeg", "-v", "error", "-y", "-fflags", "+igndts", "-i", (raw / "raw.mov").to_s,
             "-ss", (playing - started + profile[:length] - 1).round(3).to_s, "-frames:v", "1", probe.to_s)
    measured = ink(probe)
    return if measured >= 0.04

    warn("  an empty room on attempt #{attempt + 1} (ink #{measured.round(4)}), relaunching")
  end
  abort("vision never came up with a sheet after three attempts")
end

def compose_vision(profile, raw)
  times = JSON.parse((raw / "recording.json").read)
  width, height = profile[:size]
  film = WORK / "vision.mp4"
  # Level 5.1, not the 4.0 the specification names for H.264: 4.0 stops at
  # 8,192 macroblocks, and 3840×2160 is 32,400. Vision Pro's is the one size
  # 4.0 cannot carry.
  run("ffmpeg", "-v", "error", "-y", "-fflags", "+igndts", "-i", (raw / "raw.mov").to_s,
      "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
      "-ss", (times["playing"] - times["started"]).round(3).to_s, "-t", profile[:length].to_s,
      "-map", "0:v", "-map", "1:a",
      "-vf", "fps=#{FPS},scale=#{width}:#{height}:flags=lanczos,format=yuv420p",
      "-c:v", "libx264", "-profile:v", "high", "-level:v", "5.1", "-pix_fmt", "yuv420p",
      "-b:v", "30M", "-maxrate", "40M", "-bufsize", "80M", "-preset", "slow",
      "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
      "-movflags", "+faststart", film.to_s)
  seconds = `ffprobe -v error -show_entries format=duration -of csv=p=0 '#{film}'`.to_f
  puts format("%s — %dx%d, %.1fs", film, width, height, seconds)
end

# ---------------------------------------------------------------------------
# The Mac: scripted, and recorded by ScreenCaptureKit rather than simctl.

# The menu bar the plates were drawn with, in the plate's pixels, and the
# shadow the screenshots give the window (`Tools/macos-shots.rb`).
PLATE_MENU_BAR = 48
MARGIN = 36

def record_mac(profile, raw)
  recorder = WORK / "window-recorder"
  run("xcrun", "swiftc", "-O", "-parse-as-library", (Pathname.new(__dir__) / "window-recorder.swift").to_s,
      "-o", recorder.to_s)
  seed = Pathname.new(Dir.mktmpdir("tbfilm"))
  profile[:documents].each { |title, blocks| (seed / "#{title}.tortoise").write(Film.document(title, blocks)) }
  common = [
    "-project", (Film::ROOT / "TortoiseBlocks.xcodeproj").to_s, "-scheme", "TortoiseBlocks",
    "-destination", "platform=macOS", "-only-testing:TortoiseBlocksUITests/#{profile[:test]}",
    "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never"
  ]
  run("xcodebuild", "build-for-testing", *common, "-quiet")

  # The window at the app's own `defaultSize`, 1280×800pt: macOS restores a
  # saved frame in preference to it, so the saved state goes first, as the
  # screenshot rig does.
  FileUtils.rm_rf(Pathname.new(Dir.home) / "Library/Saved Application State/#{Film::BUNDLE_ID}.savedState")
  system("defaults", "delete", Film::BUNDLE_ID, out: File::NULL, err: File::NULL)

  FileUtils.rm_rf(raw)
  FileUtils.mkdir_p(raw)
  # The runner is sandboxed and can hand nothing over while it runs: the
  # recorder waits for the window on its own, the test gives it a head start,
  # and the log comes back afterwards as an attachment in the result bundle.
  input, output, capture = Open3.popen2(recorder.to_s, Film::BUNDLE_ID, "My Drawing", (raw / "raw.mov").to_s)
  waiting = Thread.new { output.gets.to_s[/started ([\d.]+)/, 1]&.to_f }
  passed = system({ "TEST_RUNNER_TB_DOCUMENTS" => seed.to_s }, "xcodebuild", "test-without-building", *common,
                  "-resultBundlePath", (raw / "test.xcresult").to_s, "-quiet")
  input.close
  capture.value
  started = waiting.value

  exported = raw / "attachments"
  FileUtils.mkdir_p(exported)
  run("xcrun", "xcresulttool", "export", "attachments", "--path", (raw / "test.xcresult").to_s,
      "--output-path", exported.to_s, out: File::NULL, err: File::NULL)
  JSON.parse((exported / "manifest.json").read).flat_map { |test| test["attachments"] }.each do |attachment|
    name = attachment["suggestedHumanReadableName"].to_s
    target = if name.start_with?("events") then raw / "events.jsonl"
             elsif name.start_with?("failure") then raw / "failure.txt"
             end
    FileUtils.cp(exported / attachment["exportedFileName"], target) if target
  end
  abort("the window recorder never started") unless started
  (raw / "recording.json").write(JSON.generate({ "started" => started }))
  FileUtils.rm_rf(seed)
  abort("#{profile[:test]} stopped part-way; #{raw / 'failure.txt'} has the window it was looking at.") unless passed
end

# The window, cut like the others, on the screenshots' desktop: the plate
# scaled to the frame's width with its bottom cropped, the window scaled to
# sit under the menu bar with its shadow. Nothing is drawn over it — the
# recorder kept the pointer and its clicks.
def compose_mac(profile, raw)
  layers = raw / "layers"
  FileUtils.mkdir_p(layers)
  cut = Film::Cut.new(raw, by_content: true)
  source = Film.upright(raw, landscape: false)
  width, height = profile[:size]
  source_w, source_h = `ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 '#{source}'`
                       .strip.split(",").map(&:to_i)

  plate = layers / "plate.png"
  plate_w, = Film.dims(Film::ROOT / profile[:plate])
  plate_scale = width.to_f / plate_w
  run("magick", (Film::ROOT / profile[:plate]).to_s, "-resize", "#{width}x", "-gravity", "north",
      "-crop", "#{width}x#{height}+0+0", "+repage", plate.to_s)
  menu_bar = (PLATE_MENU_BAR * plate_scale).round
  window_h = height - menu_bar - 2 * MARGIN
  window_w = (source_w * window_h.to_f / source_h).round
  window_w += 1 if window_w.odd?
  x = (width - window_w) / 2
  y = menu_bar + MARGIN

  # Outside its rounded corners the recorded window is black: flood-filled
  # away from each corner of one frame, which gives the corners macOS drew.
  still = layers / "still.png"
  run("ffmpeg", "-v", "error", "-y", "-i", source.to_s, "-frames:v", "1", still.to_s)
  mask = layers / "mask.png"
  corners = [[0, 0], [source_w - 1, 0], [0, source_h - 1], [source_w - 1, source_h - 1]]
  run("magick", still.to_s, "-alpha", "set", "-fuzz", "6%", "-fill", "none",
      *corners.flat_map { |cx, cy| ["-draw", "color #{cx},#{cy} floodfill"] },
      "-alpha", "extract", "-resize", "#{window_w}x#{window_h}!", mask.to_s)
  shadow = layers / "shadow.png"
  run("magick", "-size", "#{window_w}x#{window_h}", "xc:black", mask.to_s, "-alpha", "off",
      "-compose", "CopyOpacity", "-composite", "-background", "black",
      "-shadow", "55x#{(30 * plate_scale).round}+0+#{(22 * plate_scale).round}", shadow.to_s)
  offset = IO.popen(["magick", "identify", "-format", "%[fx:page.x] %[fx:page.y]", shadow.to_s], &:read)
             .split.map(&:to_i)

  length = cut.length
  abort(format("mac runs %.1fs; a preview is at most %ds.", length, LONGEST)) if length > LONGEST
  hold = [SHORTEST - length, 0].max
  inputs = ["-loop", "1", "-i", plate.to_s, "-loop", "1", "-i", shadow.to_s, "-i", source.to_s,
            "-loop", "1", "-i", mask.to_s]
  filters = [
    "[2:v]select='#{cut.select}',setpts=N/(#{FPS}*TB),scale=#{window_w}:#{window_h}:flags=lanczos,format=rgba[w0]",
    "[3:v]format=gray[m]",
    "[w0][m]alphamerge[w]",
    "[0:v][1:v]overlay=#{x + offset[0]}:#{y + offset[1]}[bg]",
    "[bg][w]overlay=#{x}:#{y}:shortest=1,format=yuv420p" +
      (hold > 0.05 ? ",tpad=stop_mode=clone:stop_duration=#{hold.round(3)}" : "") + "[v]"
  ]
  script = raw / "filters.txt"
  script.write(filters.join(";\n"))
  film = WORK / "mac.mp4"
  run("ffmpeg", "-v", "error", "-y", *inputs,
      "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
      "-/filter_complex", script.to_s, "-map", "[v]", "-map", "4:a",
      "-t", (length + hold).round(3).to_s, "-r", FPS.to_s,
      "-c:v", "libx264", "-profile:v", "high", "-level:v", "4.0", "-pix_fmt", "yuv420p",
      "-b:v", "10M", "-maxrate", "12M", "-bufsize", "24M", "-preset", "slow",
      "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
      "-movflags", "+faststart", film.to_s)
  seconds = `ffprobe -v error -show_entries format=duration -of csv=p=0 '#{film}'`.to_f
  puts format("%s — %dx%d, %.1fs (%.1fs cut), %d clicks", film, width, height, seconds, length, cut.of("tap").size)
end

# ---------------------------------------------------------------------------
# iPhone and iPad: scripted.

def compose(name, profile)
  raw = WORK / name
  layers = raw / "layers"
  FileUtils.mkdir_p(layers)
  cut = Film::Cut.new(raw)
  source = Film.upright(raw, landscape: profile[:landscape])
  width, height = profile[:size]

  # Scaled to cover the frame and centred, so a source a touch off the frame's
  # shape loses a few rows rather than gaining bars.
  source_w, source_h = `ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 '#{source}'`
                       .strip.split(",").map(&:to_i)
  scale = [width.to_f / source_w, height.to_f / source_h].max
  scaled_w = (source_w * scale).round
  scaled_h = (source_h * scale).round
  scaled_w += 1 if scaled_w.odd?
  scaled_h += 1 if scaled_h.odd?
  crop_x = (scaled_w - width) / 2
  crop_y = (scaled_h - height) / 2
  pixels = source_w / cut.points[0] * scale
  to_frame = ->(x, y, _t) { [x * pixels - crop_x, y * pixels - crop_y] }
  finger = Film.fingers(layers, (20 * pixels).round)

  length = cut.length
  abort(format("%s runs %.1fs; a preview is at most %ds.", name, length, LONGEST)) if length > LONGEST
  hold = [SHORTEST - length, 0].max

  inputs = ["-i", source.to_s]
  filters = ["[0:v]select='#{cut.select}',setpts=N/(#{FPS}*TB)," \
             "scale=#{scaled_w}:#{scaled_h}:flags=lanczos,crop=#{width}:#{height}:#{crop_x}:#{crop_y}," \
             "format=rgba[v0]"]
  last = Film.touches(cut, finger, to_frame, inputs, filters, "v0")
  filters << "[#{last}]format=yuv420p" + (hold.positive? ? ",tpad=stop_mode=clone:stop_duration=#{hold.round(3)}" : "") + "[v]"
  script = raw / "filters.txt"
  script.write(filters.join(";\n"))

  film = WORK / "#{name}.mp4"
  # Level 4.0 is the ceiling the specification names, and it covers every
  # size here: the largest, 1600×1200, is 7,500 macroblocks of its 8,192.
  run("ffmpeg", "-v", "error", "-y", *inputs,
      "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
      "-/filter_complex", script.to_s, "-map", "[v]", "-map", "#{inputs.count('-i')}:a",
      "-t", (length + hold).round(3).to_s, "-r", FPS.to_s,
      "-c:v", "libx264", "-profile:v", "high", "-level:v", "4.0", "-pix_fmt", "yuv420p",
      "-b:v", "10M", "-maxrate", "12M", "-bufsize", "24M", "-preset", "slow",
      "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
      "-movflags", "+faststart", film.to_s)
  seconds = `ffprobe -v error -show_entries format=duration -of csv=p=0 '#{film}'`.to_f
  puts format("%s — %dx%d, %.1fs (%.1fs cut%s), %d taps, %d drags",
              film, width, height, seconds, length, hold > 0.05 ? format(", %.1fs held", hold) : "",
              cut.of("tap").size, cut.of("drag").size)
end

wanted = ARGV.reject { |a| a.start_with?("-") }
chosen = wanted.empty? ? PREVIEWS : PREVIEWS.select { |name, _| wanted.include?(name) }
abort("Nothing matches #{wanted.join(', ')}; there are #{PREVIEWS.keys.join(', ')}.") if chosen.empty?

FileUtils.mkdir_p(WORK)
chosen.each do |name, profile|
  raw = WORK / name
  if profile[:mac]
    record_mac(profile, raw) unless ARGV.include?("--compose")
    compose_mac(profile, raw)
  elsif profile[:test]
    unless ARGV.include?("--compose")
      Film.record_test(udid: Film.device(profile[:device]), test: profile[:test], raw: raw,
                       work: WORK, documents: profile[:documents], phone: profile[:phone] || false)
    end
    compose(name, profile)
  else
    record_vision(profile, raw) unless ARGV.include?("--compose")
    compose_vision(profile, raw)
  end
end
