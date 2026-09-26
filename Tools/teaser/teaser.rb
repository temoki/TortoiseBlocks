#!/usr/bin/env ruby
# frozen_string_literal: true

# Makes the teaser video for the website: a child's-eye walk from one line to
# a spiral of stars, shot on the iPad simulator and cut to 1920×1080.
#
#   ruby Tools/teaser/teaser.rb             # record, then compose
#   ruby Tools/teaser/teaser.rb --compose   # compose the last recording again
#
# Silent on purpose: the music is laid on afterwards, by hand. The film lands
# in the work directory printed at the end, with the raw recording beside it.
#
# `TortoiseBlocksUITests/TeaserTests.swift` is the script — every press, when
# each caption comes up and where the camera looks. This is the camera crew
# and the editor. The README beside this file says why each piece is the way
# it is; the short version of the four things that are not tidiness:
#
# - **The recording is mostly waiting**, and the cut is what removes it. The
#   simulator writes a frame only when the screen changes, so the gaps between
#   frames *are* the still stretches; each is cut down to HEAD seconds, except
#   where the script asked for time (a caption to read, a camera move, a
#   finished drawing).
# - **The simulator records the framebuffer as it is held**: portrait, with the
#   landscape app on its side. `transpose=2` stands it up.
# - **Typing needs a hardware keyboard**, or a number field brings up half a
#   screen of keys. It is the Simulator's preference, so it is switched on for
#   the run, the device restarted to pick it up, and the preferences put back.
# - **Touches are drawn afterwards**, from the script's own log. The simulator
#   shows none, and the log knows exactly where each press went.

require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

ROOT = Pathname.new(__dir__).parent.parent
WORK = Pathname.new(Dir.tmpdir) / "tortoise-teaser"
RAW = WORK / "raw"
BUNDLE_ID = "space.hiraku.tortoiseblocks"
# The 11-inch rather than the 13-inch the App Store captures use: the same
# layout in fewer points, so every block is a quarter larger in the frame.
DEVICE_NAME = "iPad Pro 11-inch (M5)"

W = 1920
H = 1080
FPS = 30
# The current video's backdrop, left to right.
GREEN = "#39FE92"
CYAN = "#42D2F7"
INK = "1c1c1e"

# The iPad's screen in the frame: clear of the top and bottom by a little.
MARGIN = 40
RADIUS = 26

# Time, in seconds. A still screen is cut down to HEAD, except around these.
HEAD = 0.22
TAP_BEFORE = 0.35
TAP_AFTER = 0.25
# The press lands this long before the test logs it: measured against the
# first changed frame, 0.1–0.26s.
TAP_LEAD = 0.22
# A typed key has landed by the time it is logged.
KEY_BEFORE = 0.35
KEY_AFTER = 0.15
CAPTION_HOLD = 1.0
CAMERA_HOLD = 0.8
CAMERA_EASE = 0.7
# A drawing longer than this plays at FAST× — the spiral takes nine seconds.
LONG_DRAWING = 3.0
FAST = 2
DRAG_AFTER = 0.3
TITLE = 3.5
ENDING = 5.0
FADE = 0.6

def run(*command)
  system(*command) || abort("failed: #{command.join(' ')[0, 400]}")
end

def simctl(*arguments)
  IO.popen(["xcrun", "simctl", *arguments], err: %i[child out], &:read)
end

# `a+b+c+…` as a balanced tree of sums. ffmpeg's expression parser recurses
# once per `+`, and a flat sum of the ~120 pieces a cut has fails to parse
# ("Cannot allocate memory"); balanced, it is seven deep.
def sum(terms)
  return terms.first if terms.size == 1

  half = terms.size / 2
  "(#{sum(terms[0, half])}+#{sum(terms[half..-1])})"
end

def dims(file)
  `magick identify -format '%w %h' '#{file}'`.split.map(&:to_i)
end

# ---------------------------------------------------------------------------
# Recording.

# The newest iOS runtime that has the device — 27.0 or later, the same floor
# as the screenshot rig: 26.5 does not open a document handed to it by URL.
def device
  json = JSON.parse(simctl("list", "devices", "available", "-j"))
  candidates = json["devices"].flat_map do |runtime, list|
    runtime.include?("iOS") ? list.select { |d| d["name"] == DEVICE_NAME }.map { |d| [runtime, d] } : []
  end
  abort("No #{DEVICE_NAME} simulator.") if candidates.empty?
  runtime, chosen = candidates.max_by { |r, _| r }
  version = runtime[/iOS-(\d+)-(\d+)/, 0].to_s.sub("iOS-", "").tr("-", ".")
  abort("#{DEVICE_NAME} is only on iOS #{version}; 27.0 or newer is needed.") if version < "27"
  [chosen["udid"], chosen["state"]]
end

def restart(udid)
  simctl("shutdown", udid)
  simctl("boot", udid)
  simctl("bootstatus", udid)
end

def record
  udid, state = device
  puts "device #{udid}"
  if state != "Booted"
    simctl("boot", udid)
    simctl("bootstatus", udid)
  end

  # A hardware keyboard, so a number field raises no on-screen keyboard. It is
  # the Simulator's preference — Xcode 27 has no Simulator.app to attach one
  # from — so it is written first, the device restarted below to pick it up,
  # and the preferences put back afterwards.
  preferences = WORK / "simulator-preferences.plist"
  run("defaults", "export", "com.apple.iphonesimulator", preferences.to_s)
  at_exit { system("defaults", "import", "com.apple.iphonesimulator", preferences.to_s) }
  run("defaults", "write", "com.apple.iphonesimulator", "ConnectHardwareKeyboard", "-bool", "true")

  # English, said to the system as well as the app: the status bar writes the
  # date in the system's language. Whatever it was goes back afterwards.
  languages = simctl("spawn", udid, "defaults", "read", "-g", "AppleLanguages").scan(/[A-Za-z]{2,3}(?:-[A-Za-z0-9]+)*/)
  locale = simctl("spawn", udid, "defaults", "read", "-g", "AppleLocale").strip
  unless languages.first == "en-US" && locale == "en_US"
    at_exit do
      simctl("spawn", udid, "defaults", "write", "-g", "AppleLanguages", "-array", *languages)
      simctl("spawn", udid, "defaults", "write", "-g", "AppleLocale", locale)
    end
    simctl("spawn", udid, "defaults", "write", "-g", "AppleLanguages", "-array", "en-US")
    simctl("spawn", udid, "defaults", "write", "-g", "AppleLocale", "en_US")
  end
  restart(udid)
  simctl("status_bar", udid, "override",
         "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
         "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "notSupported")
  simctl("ui", udid, "appearance", "light")

  # An empty document to build in, where the test can hand it to the app: the
  # device's tmp survives the reinstall that preparing a test run does.
  seed = Pathname.new(Dir.home) / "Library/Developer/CoreSimulator/Devices" / udid / "data/tmp/tbteaser"
  FileUtils.rm_rf(seed)
  FileUtils.mkdir_p(seed)
  (seed / "My Drawing.tortoise").write(
    JSON.pretty_generate({ "blocks" => [], "schemaVersion" => 1, "title" => "My Drawing" })
  )
  events = seed / "events.jsonl"
  simctl("uninstall", udid, BUNDLE_ID)

  common = [
    "-project", (ROOT / "TortoiseBlocks.xcodeproj").to_s,
    "-scheme", "TortoiseBlocks",
    "-destination", "id=#{udid}",
    "-only-testing:TortoiseBlocksUITests/TeaserTests",
    "-parallel-testing-enabled", "NO",
    # A failed UI test otherwise spends ten minutes in `simctl diagnose`.
    "-collect-test-diagnostics", "never"
  ]
  # Built first, so the recording is not four minutes of a compiler.
  run("xcodebuild", "build-for-testing", *common, "-quiet")

  FileUtils.rm_rf(RAW)
  FileUtils.mkdir_p(RAW)
  movie = RAW / "raw.mov"
  _, output, recorder = Open3.popen2e("xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", movie.to_s)
  started = nil
  while (line = output.gets)
    next unless line.include?("Recording started")

    # The recording's own clock starts here, and the test's log is in wall
    # time, so this is what lines the two up.
    started = Time.now.to_f
    break
  end
  abort("the recorder never started") unless started

  result = RAW / "teaser.xcresult"
  environment = { "TEST_RUNNER_TB_DOCUMENTS" => seed.to_s, "TEST_RUNNER_TB_EVENTS" => events.to_s }
  passed = system(environment, "xcodebuild", "test-without-building", *common,
                  "-resultBundlePath", result.to_s, "-quiet")
  Process.kill("INT", recorder.pid)
  recorder.value
  simctl("status_bar", udid, "clear")

  FileUtils.cp(events, RAW / "events.jsonl")
  failure = Pathname.new("#{events}.failure.txt")
  FileUtils.cp(failure, RAW / "failure.txt") if failure.exist?
  (RAW / "recording.json").write(JSON.generate({ "started" => started }))
  abort("The script stopped part-way; #{RAW / 'failure.txt'} has the screen it was looking at.") unless passed
end

# ---------------------------------------------------------------------------
# Composing.

def compose
  text_tool = WORK / "text"
  run("xcrun", "swiftc", "-O", (Pathname.new(__dir__) / "text.swift").to_s, "-o", text_tool.to_s)
  text = lambda do |file, string, size, weight, colour|
    run(text_tool.to_s, file.to_s, string, size.to_s, weight, colour)
  end
  layers = WORK / "layers"
  FileUtils.mkdir_p(layers)

  events = RAW.join("events.jsonl").readlines.map { |line| JSON.parse(line) }
  started = JSON.parse(RAW.join("recording.json").read)["started"]
  at = ->(event) { event["t"] - started }
  screen = events.find { |e| e["type"] == "screen" }
  points = [screen["w"].to_f, screen["h"].to_f]
  t_start = at.call(events.find { |e| e["type"] == "start" })
  t_end = at.call(events.find { |e| e["type"] == "end" })

  # The source the right way up, at a constant rate.
  cfr = WORK / "upright.mp4"
  unless cfr.exist? && cfr.mtime > RAW.join("raw.mov").mtime
    run("ffmpeg", "-v", "error", "-y", "-i", RAW.join("raw.mov").to_s, "-vf", "transpose=2,fps=#{FPS}",
        "-c:v", "libx264", "-preset", "fast", "-crf", "10", "-pix_fmt", "yuv420p", cfr.to_s)
  end
  # While a number is being typed the caret blinks, and every blink is a
  # frame; those stretches count as still, and only the keys are kept.
  typing = events.select { |e| e["type"] == "typing" }.map { |e| [e["from"] - started, at.call(e)] }
  changes = `ffprobe -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 '#{RAW / 'raw.mov'}'`
            .split.map { |s| s.delete(",").to_f }.select { |t| t > t_start && t < t_end }
            .reject { |t| typing.any? { |a, b| t > a && t < b } }

  # A drag's phases, in recording time, worked back from when it returned.
  gesture = lambda do |e|
    distance = Math.hypot(e["x2"] - e["x"], e["y2"] - e["y"])
    release = at.call(e) - 0.05
    move_end = release - e["linger"]
    move_start = move_end - distance / e["velocity"]
    { press: move_start - e["hold"], move_start: move_start, move_end: move_end, release: release }
  end

  # What stays: the first HEAD of every still stretch, all of every moving
  # one, and whatever each event needs around it.
  windows = []
  ([t_start] + changes + [t_end]).each_cons(2) { |x, y| windows << [x, [y, x + HEAD].min] }
  events.each do |e|
    t = at.call(e)
    case e["type"]
    when "caption" then windows << [t, t + CAPTION_HOLD]
    when "camera" then windows << [t, t + CAMERA_HOLD]
    when "tap" then windows << [t - TAP_BEFORE, t + TAP_AFTER]
    when "key" then windows << [t - KEY_BEFORE, t + KEY_AFTER]
    when "drag"
      g = gesture.call(e)
      windows << [g[:press] - 0.15, g[:release] + DRAG_AFTER]
    when "linger" then windows << [t, t + e["seconds"]]
    end
  end
  windows = windows.map { |a, b| [a.clamp(t_start, t_end), b.clamp(t_start, t_end)] }.reject { |a, b| b <= a }.sort
  kept = []
  windows.each do |a, b|
    if kept.any? && a <= kept.last[1] + 1.5 / FPS
      kept.last[1] = [kept.last[1], b].max
    else
      kept << [a, b]
    end
  end
  # Takes the script threw away — a drop that did not land, tried again.
  events.select { |e| e["type"] == "cut" }.each do |e|
    a = e["from"] - started
    b = at.call(e)
    kept = kept.flat_map do |x, y|
      next [[x, y]] if y <= a || x >= b

      [[x, [y, a].min], [[x, b].max, y]].reject { |p, q| q - p < 1e-3 }
    end
  end
  # Long drawings, from the press of play to the moment they finished (the
  # linger `playDrawing` logs), are sped up; each piece carries its speed.
  drawings = []
  events.each_with_index do |e, i|
    next unless e["type"] == "linger"

    press = events[0...i].reverse.find { |p| p["type"] == "tap" }
    next unless press && at.call(e) - at.call(press) > LONG_DRAWING

    drawings << [at.call(press) + TAP_AFTER, at.call(e)]
  end
  kept = kept.flat_map do |a, b|
    cuts = drawings.flatten.select { |t| t > a && t < b }.sort
    ([a] + cuts + [b]).each_cons(2).map do |x, y|
      fast = drawings.any? { |p, q| x >= p && y <= q }
      [x, y, fast ? FAST : 1]
    end
  end
  offsets = []
  total = 0.0
  kept.each do |a, b, speed|
    offsets << total
    total += (b - a) / speed
  end
  # Recording time → film time. A moment that was cut lands where the cut is.
  map = lambda do |t|
    kept.each_with_index do |(a, b, speed), i|
      return offsets[i] if t < a
      return offsets[i] + (t - a) / speed if t <= b
    end
    total
  end
  footage = (total * FPS).floor / FPS.to_f
  puts format("kept %.1fs of %.1fs, in %d pieces", total, t_end - t_start, kept.size)

  # The screen in the frame, and the camera over it.
  screen_h = H - 2 * MARGIN
  screen_w = (screen_h * points[0] / points[1]).round
  screen_w += 1 if screen_w.odd?
  screen_x = (W - screen_w) / 2
  screen_y = MARGIN
  scale = screen_h / points[1]

  cues = events.select { |e| e["type"] == "camera" }.map do |e|
    x, y, w, h = e["rect"]
    zoom = [[points[0] / w, points[1] / h].min, 1.0].max
    { at: map.call(at.call(e)), to: [x + w / 2.0, y + h / 2.0, zoom] }
  end
  cues = [{ at: -10.0, to: [points[0] / 2, points[1] / 2, 1.0] }] + cues
  smooth = ->(u) { u = u.clamp(0.0, 1.0); u * u * (3 - 2 * u) }
  camera_at = lambda do |t|
    value = cues.first[:to].dup
    cues.each_cons(2) do |a, b|
      k = smooth.call((t - b[:at]) / CAMERA_EASE)
      3.times { |i| value[i] += (b[:to][i] - a[:to][i]) * k }
    end
    value
  end
  # The same curve, for zoompan, as a function of the film's time.
  camera_expression = lambda do |i|
    terms = ["(#{cues.first[:to][i].round(4)})"]
    cues.each_cons(2) do |a, b|
      delta = b[:to][i] - a[:to][i]
      next if delta.abs < 1e-6

      u = "clip((it-#{b[:at].round(3)})/#{CAMERA_EASE},0,1)"
      terms << "(#{delta.round(5)})*#{u}*#{u}*(3-2*#{u})"
    end
    sum(terms)
  end
  to_frame = lambda do |x, y, t|
    cx, cy, z = camera_at.call(t)
    left = (cx - points[0] / z / 2).clamp(0, points[0] - points[0] / z)
    top = (cy - points[1] / z / 2).clamp(0, points[1] - points[1] / z)
    [screen_x + (x - left) * z * scale, screen_y + (y - top) * z * scale]
  end

  # Stills: the backdrop, the screen's corners and shadow, the finger.
  background = layers / "background.png"
  run("magick", "-size", "#{H}x#{W}", "gradient:#{GREEN}-#{CYAN}", "-rotate", "-90", background.to_s)
  mask = layers / "mask.png"
  run("magick", "-size", "#{screen_w}x#{screen_h}", "xc:black", "-fill", "white",
      "-draw", "roundrectangle 0,0 #{screen_w - 1},#{screen_h - 1} #{RADIUS},#{RADIUS}", mask.to_s)
  shadow = layers / "shadow.png"
  run("magick", "-size", "#{W}x#{H}", "xc:none", "-fill", "rgba(0,70,50,0.30)",
      "-draw", "roundrectangle #{screen_x},#{screen_y + 12} #{screen_x + screen_w},#{screen_y + screen_h + 12} #{RADIUS},#{RADIUS}",
      "-blur", "0x20", shadow.to_s)

  finger = 120
  c = finger / 2
  frames = layers / "finger"
  FileUtils.rm_rf(frames)
  FileUtils.mkdir_p(frames)
  # A tap: the finger lands, then a ring spreads as it lifts. PNG32 on every
  # frame, the empty last one included — written as greyscale it has no alpha
  # and overlays as a black square.
  12.times do |i|
    p = i / 11.0
    dot_alpha = i < 7 ? 0.6 : 0.6 * (1 - (i - 6) / 5.0)
    ring_r = 24 + 30 * p
    ring_alpha = 0.9 * (1 - p)
    dot_r = 24 - 4 * [p * 2, 1].min
    run("magick", "-size", "#{finger}x#{finger}", "xc:none",
        "-fill", "rgba(255,255,255,#{dot_alpha.round(3)})",
        "-stroke", "rgba(60,60,67,#{(dot_alpha * 0.8).round(3)})", "-strokewidth", "2",
        "-draw", "circle #{c},#{c} #{c + dot_r},#{c}",
        "-fill", "none", "-stroke", "rgba(255,255,255,#{ring_alpha.round(3)})", "-strokewidth", "4",
        "-draw", "circle #{c},#{c} #{c + ring_r},#{c}", "PNG32:#{frames / format('%02d.png', i)}")
  end
  run("magick", "-size", "#{finger}x#{finger}", "xc:none", "PNG32:#{frames / '12.png'}")
  tap_movie = layers / "tap.mov"
  run("ffmpeg", "-v", "error", "-y", "-framerate", FPS.to_s, "-i", (frames / "%02d.png").to_s,
      "-c:v", "png", tap_movie.to_s)
  held = layers / "held.png"
  run("magick", "-size", "#{finger}x#{finger}", "xc:none",
      "-fill", "rgba(255,255,255,0.6)", "-stroke", "rgba(60,60,67,0.5)", "-strokewidth", "2",
      "-draw", "circle #{c},#{c} #{c + 24},#{c}", "PNG32:#{held}")

  # Captions: dark text on a white pill, low over the screen, each up until
  # the next one.
  captions = events.select { |e| e["type"] == "caption" }
  caption_layers = captions.each_with_index.map do |caption, i|
    words = layers / "caption-text-#{i}.png"
    text.call(words, caption["text"], 46, "bold", INK)
    tw, th = dims(words)
    pill_w = tw + 24
    pill_h = th - 4
    pad = 24
    file = layers / "caption-#{i}.png"
    run("magick", "-size", "#{pill_w + 2 * pad}x#{pill_h + 2 * pad}", "xc:none",
        "-fill", "rgba(0,0,0,0.22)",
        "-draw", "roundrectangle #{pad},#{pad + 4} #{pad + pill_w - 1},#{pad + pill_h + 3} #{pill_h / 2},#{pill_h / 2}",
        "-blur", "0x9",
        "-fill", "rgba(255,255,255,0.96)",
        "-draw", "roundrectangle #{pad},#{pad} #{pad + pill_w - 1},#{pad + pill_h - 1} #{pill_h / 2},#{pill_h / 2}",
        words.to_s, "-gravity", "center", "-geometry", "+0-2", "-composite", "PNG32:#{file}")
    from = map.call(at.call(caption))
    to = i + 1 < captions.size ? map.call(at.call(captions[i + 1])) : footage
    puts format("  %5.1fs  %4.1fs  %s", TITLE - FADE + from, to - from, caption["text"])
    { file: file, from: from, to: to }
  end

  taps = events.select { |e| e["type"] == "tap" }.map do |e|
    moment = map.call(at.call(e) - TAP_LEAD)
    x, y = to_frame.call(e["x"], e["y"], moment)
    { at: moment, x: (x - c).round, y: (y - c).round }
  end
  drags = events.select { |e| e["type"] == "drag" }.map do |e|
    g = gesture.call(e).transform_values { |t| map.call(t) }
    x1, y1 = to_frame.call(e["x"], e["y"], g[:press])
    x2, y2 = to_frame.call(e["x2"], e["y2"], g[:release])
    g.merge(x1: x1 - c, y1: y1 - c, x2: x2 - c, y2: y2 - c)
  end

  # The footage: cut, zoomed, framed, captioned, touched.
  select = sum(kept.map do |a, b, speed|
    piece = "between(t,#{a.round(4)},#{b.round(4)})"
    speed == 1 ? piece : "#{piece}*not(mod(n,#{speed}))"
  end)
  zx = camera_expression.call(0)
  zy = camera_expression.call(1)
  zz = camera_expression.call(2)
  inputs = ["-loop", "1", "-i", background.to_s, "-i", cfr.to_s,
            "-loop", "1", "-i", mask.to_s, "-loop", "1", "-i", shadow.to_s]
  filters = []
  filters << "[1:v]select='#{select}',setpts=N/(#{FPS}*TB)," \
             "zoompan=z='#{zz}':x='clip((#{zx})*iw/#{points[0]}-iw/zoom/2,0,iw-iw/zoom)':" \
             "y='clip((#{zy})*ih/#{points[1]}-ih/zoom/2,0,ih-ih/zoom)':d=1:s=#{screen_w}x#{screen_h}:fps=#{FPS}," \
             "format=rgba[scr0]"
  filters << "[2:v]format=gray[mask]"
  filters << "[scr0][mask]alphamerge[scr]"
  filters << "[0:v][3:v]overlay=0:0[bg]"
  filters << "[bg][scr]overlay=#{screen_x}:#{screen_y}:shortest=1[v0]"
  last = "v0"
  index = 4
  caption_layers.each_with_index do |layer, i|
    inputs += ["-loop", "1", "-i", layer[:file].to_s]
    w, h = dims(layer[:file])
    filters << "[#{index}:v]format=rgba,fade=t=in:st=#{layer[:from].round(3)}:d=0.25:alpha=1," \
               "fade=t=out:st=#{(layer[:to] - 0.25).round(3)}:d=0.25:alpha=1[c#{i}]"
    filters << "[#{last}][c#{i}]overlay=#{(W - w) / 2}:#{screen_y + screen_h - h - 18}:shortest=1[vc#{i}]"
    last = "vc#{i}"
    index += 1
  end
  taps.each_with_index do |tap, i|
    inputs += ["-i", tap_movie.to_s]
    filters << "[#{index}:v]format=rgba,setpts=PTS-STARTPTS+#{tap[:at].round(3)}/TB[t#{i}]"
    filters << "[#{last}][t#{i}]overlay=#{tap[:x]}:#{tap[:y]}:eof_action=pass[vt#{i}]"
    last = "vt#{i}"
    index += 1
  end
  drags.each_with_index do |d, i|
    inputs += ["-loop", "1", "-i", held.to_s]
    span = [d[:move_end] - d[:move_start], 0.01].max
    u = "clip((t-#{d[:move_start].round(3)})/#{span.round(3)},0,1)"
    x = "#{d[:x1].round(1)}+(#{(d[:x2] - d[:x1]).round(1)})*#{u}"
    y = "#{d[:y1].round(1)}+(#{(d[:y2] - d[:y1]).round(1)})*#{u}"
    filters << "[#{index}:v]format=rgba[h#{i}]"
    filters << "[#{last}][h#{i}]overlay=x='#{x}':y='#{y}':eval=frame:shortest=1:" \
               "enable='between(t,#{d[:press].round(3)},#{d[:release].round(3)})'[vd#{i}]"
    last = "vd#{i}"
    index += 1
    # The lift, from the tap's own animation: its second half.
    inputs += ["-i", tap_movie.to_s]
    filters << "[#{index}:v]format=rgba,trim=start=#{(6.0 / FPS).round(3)}," \
               "setpts=PTS-STARTPTS+#{d[:release].round(3)}/TB[r#{i}]"
    filters << "[#{last}][r#{i}]overlay=#{d[:x2].round}:#{d[:y2].round}:eof_action=pass[vr#{i}]"
    last = "vr#{i}"
    index += 1
  end
  footage_file = WORK / "footage.mp4"
  script = WORK / "filters.txt"
  script.write(filters.join(";\n"))
  run("ffmpeg", "-v", "error", "-y", *inputs, "-/filter_complex", script.to_s, "-map", "[#{last}]",
      "-t", footage.round(3).to_s, "-r", FPS.to_s,
      "-c:v", "libx264", "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p", footage_file.to_s)

  # The cards: the icon and the name first; the icon, the name and where it
  # runs at the end.
  icon = ROOT / "docs" / "Icon.png"
  name = layers / "name.png"
  text.call(name, "Tortoise Blocks", 104, "heavy", INK)
  devices = layers / "devices.png"
  text.call(devices, "iPad · iPhone · Mac · Apple Vision Pro", 44, "semibold", "3a3a3c")
  title = layers / "title.png"
  run("magick", background.to_s,
      "(", icon.to_s, "-resize", "340x340", ")", "-gravity", "north", "-geometry", "+0+250", "-composite",
      name.to_s, "-gravity", "north", "-geometry", "+0+620", "-composite", title.to_s)
  ending = layers / "ending.png"
  run("magick", background.to_s,
      "(", icon.to_s, "-resize", "300x300", ")", "-gravity", "north", "-geometry", "+0+215", "-composite",
      name.to_s, "-gravity", "north", "-geometry", "+0+545", "-composite",
      devices.to_s, "-gravity", "north", "-geometry", "+0+705", "-composite", ending.to_s)

  film = WORK / "teaser.mp4"
  graph = [
    "[0:v]fps=#{FPS},format=yuv420p,settb=AVTB[a]",
    "[1:v]fps=#{FPS},format=yuv420p,settb=AVTB[b]",
    "[2:v]fps=#{FPS},format=yuv420p,settb=AVTB[c]",
    "[a][b]xfade=transition=fade:duration=#{FADE}:offset=#{(TITLE - FADE).round(3)}[ab]",
    "[ab][c]xfade=transition=fade:duration=#{FADE}:offset=#{(TITLE + footage - 2 * FADE).round(3)}[v]"
  ].join(";")
  run("ffmpeg", "-v", "error", "-y",
      "-loop", "1", "-t", TITLE.to_s, "-i", title.to_s,
      "-i", footage_file.to_s,
      "-loop", "1", "-t", ENDING.to_s, "-i", ending.to_s,
      "-filter_complex", graph, "-map", "[v]",
      "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-pix_fmt", "yuv420p",
      "-movflags", "+faststart", film.to_s)
  length = `ffprobe -v error -show_entries format=duration -of csv=p=0 '#{film}'`.to_f
  puts format("%s — %.1fs, %d taps, %d drags, %d captions", film, length, taps.size, drags.size, captions.size)
end

FileUtils.mkdir_p(WORK)
record unless ARGV.include?("--compose")
compose
