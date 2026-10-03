//
//  AnimatedGIFView.swift
//  PocketSync
//

import SwiftUI
import AppKit

struct AnimatedGIFView: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.wantsLayer = true
        loadGIF(into: view)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        loadGIF(into: nsView)
    }

    private func loadGIF(into view: NSImageView) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
              let image = NSImage(contentsOf: url) else {
            return
        }

        if view.image?.name() != name {
            image.setName(name)
            view.image = image
        }

        view.animates = true
    }
}
