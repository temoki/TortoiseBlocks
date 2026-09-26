# frozen_string_literal: true

# What the teaser (`teaser.rb`) and the App Store previews (`previews.rb`)
# share: recording a UI test on a simulator, cutting the recording down to
# what moves, and drawing the touches the simulator does not show.
# `README.md` has why each piece is the way it is.

require "fileutils"
require "json"
require "open3"
require "pathname"
require "securerandom"

module Film
  ROOT = Pathname.new(__dir__).parent.parent
  BUNDLE_ID = "space.hiraku.tortoiseblocks"
  FPS = 30

  # Time, in seconds. A still screen is cut down to HEAD, except around these.
  HEAD = 0.22
  TAP_BEFORE = 0.35
  TAP_AFTER = 0.25
  # When a touch cannot be found in the recording, it is taken to have landed
  # this long before the test logged it — the iPad's typical 0.1–0.26s. A
  # phone's taps return far later, after a sheet has finished moving, which is
  # why the recording is asked first (`Cut#touch`).
  TAP_LEAD = 0.22
  # A gap between frames at least this long is the screen standing still.
  QUIET = 0.25
  # A key on a phone's number pad lights this long before the tap returns,
  # measured over six presses at 0.26s each.
  KEY_LAG = 0.26
  # A typed key has landed by the time it is logged.
  KEY_BEFORE = 0.35
  KEY_AFTER = 0.15
  CAPTION_HOLD = 1.0
  CAMERA_HOLD = 0.8
  DRAG_AFTER = 0.3
  # A drawing longer than this plays at FAST× — the teaser's spiral takes nine
  # seconds at the app's own tempo.
  LONG_DRAWING = 3.0
  FAST = 2

  module_function

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
  # The simulator.

  # The newest runtime that has the device — for iOS 27.0 or later, the same
  # floor as the screenshot rigs: 26.5 does not open a document handed to it
  # by URL.
  def device(name, os: "iOS", minimum: "27")
    json = JSON.parse(simctl("list", "devices", "available", "-j"))
    candidates = json["devices"].flat_map do |runtime, list|
      runtime.include?("SimRuntime.#{os}-") ? list.select { |d| d["name"] == name }.map { |d| [runtime, d] } : []
    end
    abort("No #{name} simulator.") if candidates.empty?
    runtime, chosen = candidates.max_by { |r, _| r }
    version = runtime[/#{os}-(\d+)-(\d+)/, 0].to_s.sub("#{os}-", "").tr("-", ".")
    abort("#{name} is only on #{os} #{version}; #{minimum} or newer is needed.") if version < minimum
    puts "#{name}: #{os} #{version}, #{chosen['udid']}"
    if chosen["state"] != "Booted"
      simctl("boot", chosen["udid"])
      simctl("bootstatus", chosen["udid"])
    end
    chosen["udid"]
  end

  def restart(udid)
    simctl("shutdown", udid)
    simctl("boot", udid)
    simctl("bootstatus", udid)
  end

  # English, a hardware keyboard, 9:41 and light — then a restart, which the
  # first two need. Everything goes back when the process ends.
  #
  # The system is told the language as well as the app because the status bar
  # writes its date in the system's. The keyboard is the Simulator's
  # preference — Xcode 27 has no Simulator.app to attach one from — and on an
  # iPad it is what keeps a number field from raising half a screen of keys. A
  # phone showed its number pad under it in one run and not in the next, so
  # `FilmTestCase.setNumber` looks for the pad rather than assuming either.
  def prepare(udid, work)
    preferences = work / "simulator-preferences-#{udid}.plist"
    run("defaults", "export", "com.apple.iphonesimulator", preferences.to_s)
    at_exit { system("defaults", "import", "com.apple.iphonesimulator", preferences.to_s) }
    run("defaults", "write", "com.apple.iphonesimulator", "ConnectHardwareKeyboard", "-bool", "true")

    languages = simctl("spawn", udid, "defaults", "read", "-g", "AppleLanguages")
                .scan(/[A-Za-z]{2,3}(?:-[A-Za-z0-9]+)*/)
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
    at_exit { simctl("status_bar", udid, "clear") }
    simctl("ui", udid, "appearance", "light")
  end

  # A document as the app writes one. `blocks` is the frozen wire format, with
  # the ids left out: each block gets a fresh one here.
  def document(title, blocks)
    identify = lambda do |block|
      kind = block.transform_values do |payload|
        next payload unless payload.is_a?(Hash) && payload["body"]

        payload.merge("body" => payload["body"].map(&identify))
      end
      { "id" => SecureRandom.uuid.upcase, "kind" => kind }
    end
    JSON.pretty_generate({ "blocks" => blocks.map(&identify), "schemaVersion" => 1, "title" => title })
  end

  # Starts `simctl io recordVideo` and returns when it has. The recording's
  # own clock starts at "Recording started", and the test's log is in wall
  # time, so the moment it says so is what lines the two up.
  def start_recording(udid, movie)
    FileUtils.rm_f(movie)
    _, output, recorder = Open3.popen2e("xcrun", "simctl", "io", udid, "recordVideo",
                                        "--codec=h264", "--force", movie.to_s)
    while (line = output.gets)
      return [recorder, Time.now.to_f] if line.include?("Recording started")
    end
    abort("the recorder never started")
  end

  def stop_recording(recorder)
    Process.kill("INT", recorder.pid)
    recorder.value
  end

  # Records one UI test into `raw`: the movie, the test's log, and the moment
  # the recording started.
  #
  # `documents` maps a title to its blocks. An iPad is handed its document by
  # URL from the device's tmp, which survives the reinstall preparing a test
  # run does, and the app is uninstalled first so an import is never renamed
  # `-1`. A phone cannot be handed one by URL, so its documents go in the app's
  # own folder — installed first so the folder exists — and nothing is
  # uninstalled, which would take them with it.
  def record_test(udid:, test:, documents:, raw:, work:, phone: false)
    prepare(udid, work)
    common = [
      "-project", (ROOT / "TortoiseBlocks.xcodeproj").to_s,
      "-scheme", "TortoiseBlocks",
      "-destination", "id=#{udid}",
      "-only-testing:TortoiseBlocksUITests/#{test}",
      "-parallel-testing-enabled", "NO",
      # A failed UI test otherwise spends ten minutes in `simctl diagnose`.
      "-collect-test-diagnostics", "never"
    ]
    # Built first, so the recording is not minutes of a compiler.
    run("xcodebuild", "build-for-testing", *common, "-quiet")

    if phone
      settings = JSON.parse(`xcodebuild -project "#{ROOT}/TortoiseBlocks.xcodeproj" -scheme TortoiseBlocks \
                             -destination "id=#{udid}" -showBuildSettings -json 2>/dev/null`).first["buildSettings"]
      simctl("install", udid, (Pathname.new(settings["BUILT_PRODUCTS_DIR"]) / settings["FULL_PRODUCT_NAME"]).to_s)
      seed = Pathname.new(simctl("get_app_container", udid, BUNDLE_ID, "data").strip) / "Documents"
      log = Pathname.new(Dir.home) / "Library/Developer/CoreSimulator/Devices" / udid / "data/tmp/tbfilm/events.jsonl"
    else
      simctl("uninstall", udid, BUNDLE_ID)
      seed = Pathname.new(Dir.home) / "Library/Developer/CoreSimulator/Devices" / udid / "data/tmp/tbfilm"
      FileUtils.rm_rf(seed)
      log = seed / "events.jsonl"
    end
    FileUtils.mkdir_p(seed)
    FileUtils.mkdir_p(log.dirname)
    documents.each { |title, blocks| (seed / "#{title}.tortoise").write(document(title, blocks)) }

    FileUtils.rm_rf(raw)
    FileUtils.mkdir_p(raw)
    recorder, started = start_recording(udid, raw / "raw.mov")
    environment = { "TEST_RUNNER_TB_DOCUMENTS" => seed.to_s, "TEST_RUNNER_TB_EVENTS" => log.to_s }
    passed = system(environment, "xcodebuild", "test-without-building", *common,
                    "-resultBundlePath", (raw / "test.xcresult").to_s, "-quiet")
    stop_recording(recorder)

    FileUtils.cp(log, raw / "events.jsonl") if log.exist?
    failure = Pathname.new("#{log}.failure.txt")
    FileUtils.cp(failure, raw / "failure.txt") if failure.exist?
    (raw / "recording.json").write(JSON.generate({ "started" => started }))
    abort("#{test} stopped part-way; #{raw / 'failure.txt'} has the screen it was looking at.") unless passed
  end

  # ---------------------------------------------------------------------------
  # The cut.

  # A recording and its log, read back, with the recording cut down to what
  # moves: the first HEAD of every still stretch, all of every moving one, and
  # whatever each logged event needs around it. `map` takes recording time to
  # film time; `select` is the ffmpeg expression that keeps those frames.
  class Cut
    attr_reader :events, :points, :kept, :total, :started

    # `by_content` is for recordings that write frames whether or not
    # anything changed — ScreenCaptureKit on a display, which the Mac's is.
    # There a frame counts as a change only if `mpdecimate` keeps it.
    def initialize(raw, by_content: false)
      @raw = raw
      @frames =
        if by_content
          `ffmpeg -hide_banner -fflags +igndts -i '#{raw / 'raw.mov'}' -vf scale=640:-1,mpdecimate,showinfo -f null - 2>&1`
            .scan(/pts_time:([\d.]+)/).flatten.map(&:to_f).sort
        else
          `ffprobe -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 '#{raw / 'raw.mov'}'`
            .split.map { |f| f.delete(",").to_f }.sort
        end
      @events = raw.join("events.jsonl").readlines.map { |line| JSON.parse(line) }
      @started = JSON.parse(raw.join("recording.json").read)["started"]
      screen = @events.find { |e| e["type"] == "screen" }
      @points = [screen["w"].to_f, screen["h"].to_f]
      @t_start = at(@events.find { |e| e["type"] == "start" })
      @t_end = at(@events.find { |e| e["type"] == "end" })
      @typing = of("typing").map { |e| [e["from"] - @started, at(e)] }
      cut
    end

    def at(event)
      event["t"] - @started
    end

    def of(type)
      @events.select { |e| e["type"] == type }
    end

    # When a tap's touch landed, in recording time: the first frame, after
    # the tap was called, that breaks a stillness. XCUITest waits for the app to
    # go idle before it touches, so the touch is what ends the quiet — and the
    # log's own time, written once the app is idle again, can be a second and
    # a half later on a phone, where a sheet has to finish moving first.
    #
    # Not "the burst the tap returned in": a sheet that has settled can still
    # draw one late frame, and that frame is not the touch.
    #
    # Keys pressed one after another on a number pad are the exception: the
    # last key's release is still drawing when the next goes down, so there is
    # no stillness to break. Those return a steady KEY_LAG after the press.
    def touch(e)
      t = at(e)
      return t - KEY_LAG if @typing.any? { |a, b| t > a && t < b }

      floor = e["t0"] ? e["t0"] - @started : t - 2.5
      landed = @frames.each_cons(2).find { |earlier, later| later > floor && later <= t + 0.02 && later - earlier >= QUIET }
      landed ? landed[1] : t - TAP_LEAD
    end

    # A drag's phases, in recording time, worked back from when it returned.
    def gesture(e)
      distance = Math.hypot(e["x2"] - e["x"], e["y2"] - e["y"])
      release = at(e) - 0.05
      move_end = release - e["linger"]
      move_start = move_end - distance / e["velocity"]
      { press: move_start - e["hold"], move_start: move_start, move_end: move_end, release: release }
    end

    # Recording time → film time. A moment that was cut lands where the cut is.
    def map(t)
      @kept.each_with_index do |(a, b, speed), i|
        return @offsets[i] if t < a
        return @offsets[i] + (t - a) / speed if t <= b
      end
      @total
    end

    # The whole film, in whole frames.
    def length
      (@total * FPS).floor / FPS.to_f
    end

    def select
      Film.sum(@kept.map do |a, b, speed|
        piece = "between(t,#{a.round(4)},#{b.round(4)})"
        speed == 1 ? piece : "#{piece}*not(mod(n,#{speed}))"
      end)
    end

    private

    def cut
      # While a number is being typed the caret blinks, and every blink is a
      # frame; those stretches count as still, and only the keys are kept.
      changes = @frames.select { |t| t > @t_start && t < @t_end }
                       .reject { |t| @typing.any? { |a, b| t > a && t < b } }

      windows = []
      ([@t_start] + changes + [@t_end]).each_cons(2) { |x, y| windows << [x, [y, x + HEAD].min] }
      @events.each do |e|
        t = at(e)
        case e["type"]
        when "caption" then windows << [t, t + CAPTION_HOLD]
        when "camera" then windows << [t, t + CAMERA_HOLD]
        when "tap"
          landed = touch(e)
          windows << [landed - TAP_BEFORE, landed + TAP_AFTER]
        when "key" then windows << [t - KEY_BEFORE, t + KEY_AFTER]
        when "drag"
          g = gesture(e)
          windows << [g[:press] - 0.15, g[:release] + DRAG_AFTER]
        when "linger" then windows << [t, t + e["seconds"]]
        end
      end
      windows = windows.map { |a, b| [a.clamp(@t_start, @t_end), b.clamp(@t_start, @t_end)] }
                       .reject { |a, b| b <= a }.sort
      kept = []
      windows.each do |a, b|
        if kept.any? && a <= kept.last[1] + 1.5 / FPS
          kept.last[1] = [kept.last[1], b].max
        else
          kept << [a, b]
        end
      end

      # Takes the script threw away — a drop that did not land, tried again.
      of("cut").each do |e|
        a = e["from"] - @started
        b = at(e)
        kept = kept.flat_map do |x, y|
          next [[x, y]] if y <= a || x >= b

          [[x, [y, a].min], [[x, b].max, y]].reject { |p, q| q - p < 1e-3 }
        end
      end

      # Long drawings, from the press of play to the moment they finished (the
      # linger `playDrawing` logs), are sped up; each piece carries its speed.
      drawings = []
      @events.each_with_index do |e, i|
        next unless e["type"] == "linger"

        press = @events[0...i].reverse.find { |p| p["type"] == "tap" }
        next unless press && at(e) - at(press) > LONG_DRAWING

        drawings << [touch(press) + TAP_AFTER, at(e)]
      end
      @kept = kept.flat_map do |a, b|
        cuts = drawings.flatten.select { |t| t > a && t < b }.sort
        ([a] + cuts + [b]).each_cons(2).map do |x, y|
          fast = drawings.any? { |p, q| x >= p && y <= q }
          [x, y, fast ? FAST : 1]
        end
      end

      @offsets = []
      @total = 0.0
      @kept.each do |a, b, speed|
        @offsets << @total
        @total += (b - a) / speed
      end
    end
  end

  # The recording the right way up, at a constant rate: the simulator writes a
  # frame only when the screen changes, and holds a landscape screen on its
  # side. Kept beside the raw movie and remade only when that changes.
  def upright(raw, landscape:)
    movie = raw / "upright.mp4"
    return movie if movie.exist? && movie.mtime > raw.join("raw.mov").mtime

    # `igndts`: the recorder writes decode times that drift from the
    # presentation times — eleven seconds apart by the end of one phone
    # recording — and without it the conversion followed the wrong clock, so
    # the film cut to the home screen before the drawing had finished.
    filters = [landscape ? "transpose=2" : nil, "fps=#{FPS}"].compact.join(",")
    run("ffmpeg", "-v", "error", "-y", "-fflags", "+igndts", "-i", raw.join("raw.mov").to_s, "-vf", filters,
        "-c:v", "libx264", "-preset", "fast", "-crf", "10", "-pix_fmt", "yuv420p", movie.to_s)
    movie
  end

  # ---------------------------------------------------------------------------
  # Touches.

  # The finger, `radius` pixels: a tap is a clip (it lands, then a ring spreads
  # as it lifts); a held finger, for drags, is a still.
  #
  # PNG32 on every frame, the empty last one included — written as greyscale
  # it has no alpha, and overlays as a black square.
  def fingers(layers, radius)
    size = (radius * 5).round
    size += 1 if size.odd?
    c = size / 2
    frames = layers / "finger"
    FileUtils.rm_rf(frames)
    FileUtils.mkdir_p(frames)
    12.times do |i|
      p = i / 11.0
      dot_alpha = i < 7 ? 0.6 : 0.6 * (1 - (i - 6) / 5.0)
      ring_r = radius * (1 + 1.25 * p)
      ring_alpha = 0.9 * (1 - p)
      dot_r = radius * (1 - [p * 2, 1].min / 6.0)
      stroke = [radius / 12.0, 1.5].max
      run("magick", "-size", "#{size}x#{size}", "xc:none",
          "-fill", "rgba(255,255,255,#{dot_alpha.round(3)})",
          "-stroke", "rgba(60,60,67,#{(dot_alpha * 0.8).round(3)})", "-strokewidth", stroke.round(1).to_s,
          "-draw", "circle #{c},#{c} #{(c + dot_r).round(1)},#{c}",
          "-fill", "none", "-stroke", "rgba(255,255,255,#{ring_alpha.round(3)})",
          "-strokewidth", (stroke * 2).round(1).to_s,
          "-draw", "circle #{c},#{c} #{(c + ring_r).round(1)},#{c}", "PNG32:#{frames / format('%02d.png', i)}")
    end
    run("magick", "-size", "#{size}x#{size}", "xc:none", "PNG32:#{frames / '12.png'}")
    tap = layers / "tap.mov"
    run("ffmpeg", "-v", "error", "-y", "-framerate", FPS.to_s, "-i", (frames / "%02d.png").to_s,
        "-c:v", "png", tap.to_s)
    held = layers / "held.png"
    run("magick", "-size", "#{size}x#{size}", "xc:none",
        "-fill", "rgba(255,255,255,0.6)", "-stroke", "rgba(60,60,67,0.5)",
        "-strokewidth", ([radius / 12.0, 1.5].max).round(1).to_s,
        "-draw", "circle #{c},#{c} #{c + radius},#{c}", "PNG32:#{held}")
    { tap: tap, held: held, half: c }
  end

  # Adds every logged touch to a filter graph: `inputs` and `filters` grow,
  # and the label of the last stage is returned. `to_frame.(x, y, t)` places a
  # screen point in the frame at film time t.
  def touches(cut, finger, to_frame, inputs, filters, last)
    index = inputs.count("-i")
    cut.of("tap").each_with_index do |e, i|
      moment = cut.map(cut.touch(e) - 1.0 / FPS)
      x, y = to_frame.call(e["x"], e["y"], moment)
      inputs.push("-i", finger[:tap].to_s)
      filters << "[#{index}:v]format=rgba,setpts=PTS-STARTPTS+#{moment.round(3)}/TB[t#{i}]"
      filters << "[#{last}][t#{i}]overlay=#{(x - finger[:half]).round}:#{(y - finger[:half]).round}:" \
                 "eof_action=pass[vt#{i}]"
      last = "vt#{i}"
      index += 1
    end
    cut.of("drag").each_with_index do |e, i|
      g = cut.gesture(e).transform_values { |t| cut.map(t) }
      x1, y1 = to_frame.call(e["x"], e["y"], g[:press]).map { |v| v - finger[:half] }
      x2, y2 = to_frame.call(e["x2"], e["y2"], g[:release]).map { |v| v - finger[:half] }
      span = [g[:move_end] - g[:move_start], 0.01].max
      u = "clip((t-#{g[:move_start].round(3)})/#{span.round(3)},0,1)"
      inputs.push("-loop", "1", "-i", finger[:held].to_s)
      filters << "[#{index}:v]format=rgba[h#{i}]"
      filters << "[#{last}][h#{i}]overlay=x='#{x1.round(1)}+(#{(x2 - x1).round(1)})*#{u}':" \
                 "y='#{y1.round(1)}+(#{(y2 - y1).round(1)})*#{u}':eval=frame:shortest=1:" \
                 "enable='between(t,#{g[:press].round(3)},#{g[:release].round(3)})'[vd#{i}]"
      last = "vd#{i}"
      index += 1
      # The lift, from the tap's own animation: its second half.
      inputs.push("-i", finger[:tap].to_s)
      filters << "[#{index}:v]format=rgba,trim=start=#{(6.0 / FPS).round(3)}," \
                 "setpts=PTS-STARTPTS+#{g[:release].round(3)}/TB[r#{i}]"
      filters << "[#{last}][r#{i}]overlay=#{x2.round}:#{y2.round}:eof_action=pass[vr#{i}]"
      last = "vr#{i}"
      index += 1
    end
    last
  end
end
