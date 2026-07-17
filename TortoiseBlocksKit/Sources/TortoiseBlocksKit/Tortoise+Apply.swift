import TortoiseCore

extension Tortoise {
    /// Replays a command stream through the public `Tortoise` API, so an
    /// expanded block program can be fed to a canvas as-is.
    ///
    /// For well-formed streams (the only kind `BlockExpander` produces) the
    /// recorded `commands` equal the input, which `TortoisePlayer`'s
    /// `currentCommandIndex` relies on for block highlighting.
    public func apply(_ commands: [TortoiseCommand]) {
        for command in commands {
            apply(command)
        }
    }

    /// Replays a single command through the public `Tortoise` API.
    public func apply(_ command: TortoiseCommand) {
        switch command {
        case .forward(let distance): forward(distance)
        case .rotate(let degrees): right(degrees)
        case .home: home()
        case .setPosition(let position): setPosition(position)
        case .setHeading(let degrees): heading = degrees
        case .penDown: penDown()
        case .penUp: penUp()
        case .penColor(let color): penColor = color
        case .penWidth(let width): penWidth = width
        case .fillColor(let color): fillColor = color
        case .beginFill: beginFill()
        case .endFill: endFill()
        case .showTortoise: showTortoise()
        case .hideTortoise: hideTortoise()
        case .speed(let value): speed = value
        case .backgroundColor(let color): backgroundColor = color
        case .clear: clear()
        case .arc(let radius, let extent): circle(radius: radius, extent: extent)
        case .dot(let size): dot(size: size)
        }
    }
}
