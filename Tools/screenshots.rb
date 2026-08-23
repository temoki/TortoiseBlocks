#!/usr/bin/env ruby
# frozen_string_literal: true

# Makes appstore/screenshots sendable, and rebuilds the copies the website uses.
#
#   ruby Tools/screenshots.rb            # the usual run, after a reshoot
#   ruby Tools/screenshots.rb --all      # re-optimise every capture, not just new ones
#
# **Every capture arrives with an alpha channel**, and App Store Connect
# refuses one. That is not carelessness at the export step: the Mac shots are
# composed in Figma and the iPad ones come from the simulator's screenshot
# button, and neither can be told to write RGB. So the channel is removed here
# rather than argued with there — and since it has always been fully opaque,
# removing it is lossless. That is checked, not assumed: a capture with real
# transparency stops the run, because compositing it onto a background this
# script picked would silently change the picture.
#
# It then does the step that is easy to forget, having been forgotten twice:
# site/shots/*.png are downscaled copies of seven of these captures, so a
# reshoot that stops at appstore/ leaves the website showing the previous
# build's UI. They are regenerated every run. The derivation is deterministic —
# rerunning it against unchanged captures reproduces the committed files byte
# for byte — so a no-op run leaves the working tree clean.
#
# Needs `magick` (ImageMagick 7) and `oxipng`, both from Homebrew. It ends by
# running the same check CI runs, so a green finish means the tree is sendable.
#
# One thing to expect from `--all`: oxipng at `-o max` is not bit-for-bit
# reproducible across runs, so re-optimising an already-optimal capture can
# rewrite it by a few dozen bytes with the pixels untouched. That is noise in a
# diff, not a change, and it is the reason the default run only touches what it
# just flattened.

require "fileutils"
require "pathname"
require "tmpdir"

require_relative "../fastlane/metadata_check"

ROOT = Pathname.new(__dir__).parent
SCREENSHOTS = ROOT / "appstore" / "screenshots"
SITE_SHOTS = ROOT / "site" / "shots"
DOCS = ROOT / "docs"

# Which captures the website uses, and how big. A curated subset rather than a
# rule — the code pane is on the Mac half of the page and not the iPad half —
# so it is a table, and a new site image has to be added to it by hand.
DERIVED = {
  "ios" => {
    prefix: "ipad",
    size: "1600x1200",
    locales: { "en-US" => "en", "ja" => "ja" },
    shots: { "1_star_canvas" => "1", "2_spiral_canvas" => "2", "4_tree_canvas" => "4" }
  },
  "macos" => {
    prefix: "mac",
    size: "1400x875",
    locales: { "en-US" => "en", "ja" => "ja" },
    # The star went to the Vision Pro row when the platform section got a
    # picture of its own; the code pane is the Mac's remaining job on the page.
    shots: { "3_spiral_code" => "3" }
  },
  # One is enough: the drawing on the table is the whole of what this platform
  # adds, and every visitor downloads both languages' images.
  "visionos" => {
    prefix: "vision",
    size: "1400x788",
    locales: { "en-US" => "en", "ja" => "ja" },
    shots: { "1_star_table" => "1" }
  }
}.freeze

# The README's two pictures, on the same terms as the site copies and for the
# same reason: what a reshoot silently leaves behind is the picture nobody has
# open while shooting. Same recipe, too — quantised to 256 colours — which is
# what makes rerunning this reproduce the committed files rather than rewrite
# them.
#
# The Mac one is the *tree* on purpose. It is the only capture in the set that
# shows a block calling itself, which is what the README spends its longest
# bullet on, and the platform section is the Mac's other job on the page
# already. Both README images were composed by hand before the rigs existed —
# the same scenes, shot separately — so this refreshes them rather than
# replacing them, and the window sits a little differently for it.
DOCS_DERIVED = {
  "macos/en-US/4_tree_canvas" => { target: "Screenshot.png", size: "2560x1600" },
  "visionos/en-US/1_star_table" => { target: "Viewer.png", size: "1600x900" }
}.freeze

def run(*command)
  return if system(*command)

  abort("failed: #{command.join(' ')}")
end

def captures
  Pathname.glob(SCREENSHOTS / "*" / "*" / "*.png").sort
end

def relative(path)
  path.relative_path_from(ROOT)
end

# Drops the alpha channel, refusing anything that is not already opaque.
#
# `-alpha off` discards the channel and leaves RGB untouched, which is what
# makes this lossless. Compositing (`-background white -flatten`) would not be:
# it would need a colour, and the right colour is whatever the capture was
# taken against.
def flatten(path)
  # No shell in the way, so no quoting to get wrong.
  opaque = IO.popen(["magick", "identify", "-format", "%[opaque]", path.to_s], &:read).strip
  unless opaque.casecmp("true").zero?
    abort("#{relative(path)} has real transparency, not just an unused channel — " \
          "flattening it would need a background colour, which is a decision for a person")
  end

  puts "flattening #{relative(path)}"
  Dir.mktmpdir do |tmp|
    out = File.join(tmp, path.basename.to_s)
    run("magick", path.to_s, "-alpha", "off", out)
    FileUtils.cp(out, path)
  end
end

all = ARGV.include?("--all")

flattened = captures.select { |path| MetadataCheck.alpha?(path) }
flattened.each { |path| flatten(path) }

# Only what changed, unless asked otherwise: `-o max` searches hard enough that
# re-running it over a set that is already optimal costs minutes and saves
# nothing.
optimise = all ? captures : flattened
unless optimise.empty?
  puts "optimising #{optimise.count} capture(s) — this takes a while at -o max"
  run("oxipng", "-q", "-o", "max", "--strip", "safe", *optimise.map(&:to_s))
end

DERIVED.each do |platform, spec|
  spec[:locales].each do |locale, short|
    spec[:shots].each do |capture, index|
      source = SCREENSHOTS / platform / locale / "#{capture}.png"
      next warn("missing #{relative(source)}, skipping its site copy") unless source.exist?

      target = SITE_SHOTS / "#{spec[:prefix]}-#{short}-#{index}.png"
      run("magick", source.to_s, "-resize", spec[:size], "-dither", "None",
          "-colors", "256", "-strip", target.to_s)
    end
  end
end
run("oxipng", "-q", "-o", "max", "--strip", "safe", *Pathname.glob(SITE_SHOTS / "*.png").map(&:to_s))
puts "site/shots regenerated"

DOCS_DERIVED.each do |capture, spec|
  source = SCREENSHOTS / "#{capture}.png"
  next warn("missing #{relative(source)}, skipping docs/#{spec[:target]}") unless source.exist?

  target = DOCS / spec[:target]
  run("magick", source.to_s, "-resize", spec[:size], "-dither", "None",
      "-colors", "256", "-strip", target.to_s)
  run("oxipng", "-q", "-o", "max", "--strip", "safe", target.to_s)
end
puts "docs images regenerated"

exit(MetadataCheck.report ? 0 : 1)
