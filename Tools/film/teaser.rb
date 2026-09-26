#!/usr/bin/env ruby
# frozen_string_literal: true

# Makes the teaser video for the website: a child's-eye walk from one line to
# a spiral of stars, shot on the iPad simulator and cut to 1920×1080.
#
#   ruby Tools/film/teaser.rb             # record, then compose
#   ruby Tools/film/teaser.rb --compose   # compose the last recording again
#
# Silent on purpose: the music is laid on afterwards, by hand. The film lands
# in the work directory printed at the end, with the raw recording beside it.
#
# `TortoiseBlocksUITests/TeaserTests.swift` is the script — every press, when
# each caption comes up and where the camera looks. `film.rb` records it and
# cuts it down to what moves; this frames it: the backdrop, the camera, the
# captions and the cards at either end. The README beside this file says why
# each piece is the way it is.

require "tmpdir"
require_relative "film"

WORK = Pathname.new(Dir.tmpdir) / "tortoise-teaser"
RAW = WORK / "raw"
# The 11-inch rather than the 13-inch the App Store captures use: the same
# layout in fewer points, so every block is a quarter larger in the frame.
DEVICE_NAME = "iPad Pro 11-inch (M5)"

W = 1920
H = 1080
FPS = Film::FPS
# The previous video's backdrop, left to right.
GREEN = "#39FE92"
CYAN = "#42D2F7"
INK = "1c1c1e"
# The iPad's screen in the frame: clear of the top and bottom by a little.
MARGIN = 40
RADIUS = 26
CAMERA_EASE = 0.7
TITLE = 3.5
ENDING = 5.0
FADE = 0.6

def run(*command)
  Film.run(*command)
end

def compose
  text_tool = WORK / "text"
  run("xcrun", "swiftc", "-O", (Pathname.new(__dir__) / "text.swift").to_s, "-o", text_tool.to_s)
  text = lambda do |file, string, size, weight, colour|
    run(text_tool.to_s, file.to_s, string, size.to_s, weight, colour)
  end
  layers = WORK / "layers"
  FileUtils.mkdir_p(layers)

  cut = Film::Cut.new(RAW)
  points = cut.points
  footage = cut.length
  source = Film.upright(RAW, landscape: true)
  puts format("kept %.1fs, in %d pieces", cut.total, cut.kept.size)

  # The screen in the frame, and the camera over it.
  screen_h = H - 2 * MARGIN
  screen_w = (screen_h * points[0] / points[1]).round
  screen_w += 1 if screen_w.odd?
  screen_x = (W - screen_w) / 2
  screen_y = MARGIN
  scale = screen_h / points[1]

  cues = cut.of("camera").map do |e|
    x, y, w, h = e["rect"]
    zoom = [[points[0] / w, points[1] / h].min, 1.0].max
    { at: cut.map(cut.at(e)), to: [x + w / 2.0, y + h / 2.0, zoom] }
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
    Film.sum(terms)
  end
  to_frame = lambda do |x, y, t|
    cx, cy, z = camera_at.call(t)
    left = (cx - points[0] / z / 2).clamp(0, points[0] - points[0] / z)
    top = (cy - points[1] / z / 2).clamp(0, points[1] - points[1] / z)
    [screen_x + (x - left) * z * scale, screen_y + (y - top) * z * scale]
  end

  # Stills: the backdrop, the screen's corners and shadow.
  background = layers / "background.png"
  run("magick", "-size", "#{H}x#{W}", "gradient:#{GREEN}-#{CYAN}", "-rotate", "-90", background.to_s)
  mask = layers / "mask.png"
  run("magick", "-size", "#{screen_w}x#{screen_h}", "xc:black", "-fill", "white",
      "-draw", "roundrectangle 0,0 #{screen_w - 1},#{screen_h - 1} #{RADIUS},#{RADIUS}", mask.to_s)
  shadow = layers / "shadow.png"
  run("magick", "-size", "#{W}x#{H}", "xc:none", "-fill", "rgba(0,70,50,0.30)",
      "-draw", "roundrectangle #{screen_x},#{screen_y + 12} #{screen_x + screen_w},#{screen_y + screen_h + 12} #{RADIUS},#{RADIUS}",
      "-blur", "0x20", shadow.to_s)
  finger = Film.fingers(layers, 24)

  # Captions: dark text on a white pill, low over the screen, each up until
  # the next one.
  captions = cut.of("caption")
  caption_layers = captions.each_with_index.map do |caption, i|
    words = layers / "caption-text-#{i}.png"
    text.call(words, caption["text"], 46, "bold", INK)
    tw, th = Film.dims(words)
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
    from = cut.map(cut.at(caption))
    to = i + 1 < captions.size ? cut.map(cut.at(captions[i + 1])) : footage
    puts format("  %5.1fs  %4.1fs  %s", TITLE - FADE + from, to - from, caption["text"])
    { file: file, from: from, to: to }
  end

  # The footage: cut, zoomed, framed, captioned, touched.
  zx = camera_expression.call(0)
  zy = camera_expression.call(1)
  zz = camera_expression.call(2)
  inputs = ["-loop", "1", "-i", background.to_s, "-i", source.to_s,
            "-loop", "1", "-i", mask.to_s, "-loop", "1", "-i", shadow.to_s]
  filters = []
  filters << "[1:v]select='#{cut.select}',setpts=N/(#{FPS}*TB)," \
             "zoompan=z='#{zz}':x='clip((#{zx})*iw/#{points[0]}-iw/zoom/2,0,iw-iw/zoom)':" \
             "y='clip((#{zy})*ih/#{points[1]}-ih/zoom/2,0,ih-ih/zoom)':d=1:s=#{screen_w}x#{screen_h}:fps=#{FPS}," \
             "format=rgba[scr0]"
  filters << "[2:v]format=gray[mask]"
  filters << "[scr0][mask]alphamerge[scr]"
  filters << "[0:v][3:v]overlay=0:0[bg]"
  filters << "[bg][scr]overlay=#{screen_x}:#{screen_y}:shortest=1[v0]"
  last = "v0"
  caption_layers.each_with_index do |layer, i|
    index = inputs.count("-i")
    inputs.push("-loop", "1", "-i", layer[:file].to_s)
    w, h = Film.dims(layer[:file])
    filters << "[#{index}:v]format=rgba,fade=t=in:st=#{layer[:from].round(3)}:d=0.25:alpha=1," \
               "fade=t=out:st=#{(layer[:to] - 0.25).round(3)}:d=0.25:alpha=1[c#{i}]"
    filters << "[#{last}][c#{i}]overlay=#{(W - w) / 2}:#{screen_y + screen_h - h - 18}:shortest=1[vc#{i}]"
    last = "vc#{i}"
  end
  last = Film.touches(cut, finger, to_frame, inputs, filters, last)
  footage_file = WORK / "footage.mp4"
  script = WORK / "filters.txt"
  script.write(filters.join(";\n"))
  run("ffmpeg", "-v", "error", "-y", *inputs, "-/filter_complex", script.to_s, "-map", "[#{last}]",
      "-t", footage.round(3).to_s, "-r", FPS.to_s,
      "-c:v", "libx264", "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p", footage_file.to_s)

  # The cards: the icon and the name first; the icon, the name and where it
  # runs at the end.
  icon = Film::ROOT / "docs" / "Icon.png"
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
  puts format("%s — %.1fs, %d taps, %d drags, %d captions",
              film, length, cut.of("tap").size, cut.of("drag").size, captions.size)
end

FileUtils.mkdir_p(WORK)
unless ARGV.include?("--compose")
  Film.record_test(udid: Film.device(DEVICE_NAME), test: "TeaserTests", raw: RAW, work: WORK,
                   documents: { "My Drawing" => [] })
end
compose
