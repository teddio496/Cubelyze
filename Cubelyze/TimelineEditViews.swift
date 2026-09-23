import AppKit
import SwiftUI

struct TimelineIntervalBar: View {
    @ObservedObject var playback: PlaybackModel
    let annotation: VideoAnnotation
    let spanWidth: CGFloat
    let timelineWidth: CGFloat

    private enum Part { case start, end, body }
    @State private var hovered = false
    @State private var activePart: Part?
    @State private var dragOrigin: (start: Double, end: Double)?

    private var current: VideoAnnotation {
        playback.annotations.first(where: { $0.id == annotation.id }) ?? annotation
    }

    private var showsHandles: Bool {
        hovered || activePart != nil || playback.selectedAnnotationID == annotation.id
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(annotation.category.color.opacity(0.55))
                .frame(width: spanWidth, height: 26)
                .overlay(alignment: .leading) {
                    if spanWidth >= 75 {
                        Text(annotation.category.title)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                }
                .overlay {
                    if playback.selectedAnnotationID == annotation.id {
                        RoundedRectangle(cornerRadius: 3).stroke(.primary, lineWidth: 2)
                    }
                }
                .frame(width: max(18, spanWidth), height: 26, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { playback.selectAnnotation(annotation) }
                .gesture(drag(.body))
                .offset(x: 9)

            if showsHandles {
                handle(.start)
                handle(.end).offset(x: spanWidth)
            }
        }
        .frame(width: max(18, spanWidth) + 18, height: 26, alignment: .leading)
        .onHover { inside in
            hovered = inside
            (inside ? NSCursor.openHand : NSCursor.arrow).set()
        }
        .overlay(alignment: .topLeading) {
            if activePart != nil, let end = current.timing.end {
                Text("\(PlaybackModel.timestamp(current.timing.start))–\(PlaybackModel.timestamp(end))  ·  \(PlaybackModel.timestamp(end - current.timing.start))")
                    .font(.caption2).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .fixedSize()
                    .offset(y: -25)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(activePart == nil ? 0 : 10)
        .help("Drag bar to move; drag its edges to resize")
        .accessibilityLabel("\(annotation.category.title) interval; drag edges to resize or bar to move")
    }

    private func handle(_ part: Part) -> some View {
        Capsule()
            .fill(.primary)
            .frame(width: 3, height: 19)
            .frame(width: 18, height: 26)
            .contentShape(Rectangle())
            .onHover { inside in (inside ? NSCursor.resizeLeftRight : NSCursor.openHand).set() }
            .gesture(drag(part))
            .help(part == .start ? "Adjust start" : "Adjust end")
    }

    private func drag(_ part: Part) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in apply(part, translation: value.translation.width, commit: false) }
            .onEnded { value in
                apply(part, translation: value.translation.width, commit: true)
                dragOrigin = nil
                activePart = nil
            }
    }

    private func apply(_ part: Part, translation: CGFloat, commit: Bool) {
        guard let originalEnd = annotation.timing.end, timelineWidth > 0,
              playback.duration > 0 else { return }
        if dragOrigin == nil {
            dragOrigin = (annotation.timing.start, originalEnd)
            playback.selectAnnotation(annotation, seek: false)
        }
        guard let origin = dragOrigin else { return }
        activePart = part
        let delta = Double(translation / timelineWidth) * playback.duration
        let minimum = 0.001
        let start: Double
        let end: Double
        switch part {
        case .start:
            start = min(max(0, origin.start + delta), origin.end - minimum)
            end = origin.end
        case .end:
            start = origin.start
            end = max(min(playback.duration, origin.end + delta), origin.start + minimum)
        case .body:
            let shift = min(max(-origin.start, delta), playback.duration - origin.end)
            start = origin.start + shift
            end = origin.end + shift
        }
        guard playback.updateAnnotationInterval(id: annotation.id, start: start,
                                                end: end, commit: commit) else { return }
        playback.seekForTimelineEdit(to: part == .end ? end : start, final: commit)
    }
}

struct TimelineSegmentBoundary: View {
    @ObservedObject var playback: PlaybackModel
    let right: SolveSegment
    let timelineWidth: CGFloat

    @State private var hovered = false
    @State private var origin: Double?
    @State private var dragging = false

    private var rightIndex: Int? { playback.segments.firstIndex(where: { $0.id == right.id }) }

    var body: some View {
        ZStack {
            if hovered || dragging {
                RoundedRectangle(cornerRadius: 3).fill(.blue.opacity(0.18))
            }
            Capsule()
                .fill(Color.blue)
                .frame(width: hovered || dragging ? 4 : 2, height: 42)
        }
        .frame(width: 18, height: 42)
        .contentShape(Rectangle())
        .onHover { inside in
            hovered = inside
            (inside ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
        }
        .onTapGesture { playback.selectSegment(right) }
        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in apply(value.translation.width, commit: false) }
            .onEnded { value in
                apply(value.translation.width, commit: true)
                origin = nil
                dragging = false
            })
        .overlay(alignment: .topLeading) {
            if dragging, let index = rightIndex, index > 0 {
                let left = playback.segments[index - 1]
                let currentRight = playback.segments[index]
                Text("\(PlaybackModel.timestamp(currentRight.start))  ·  \(left.type.title) \(PlaybackModel.timestamp(left.duration))  |  \(currentRight.type.title) \(PlaybackModel.timestamp(currentRight.duration))")
                    .font(.caption2).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .fixedSize()
                    .offset(y: -25)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(dragging ? 10 : 1)
        .help("Drag to move the shared segment boundary")
        .accessibilityLabel("Boundary before \(right.type.title); drag to adjust adjacent phases")
    }

    private func apply(_ translation: CGFloat, commit: Bool) {
        guard timelineWidth > 0, playback.duration > 0,
              let index = rightIndex, index > 0 else { return }
        if origin == nil {
            origin = playback.segments[index].start
            playback.selectSegment(right, seek: false)
        }
        guard let origin else { return }
        dragging = true
        let left = playback.segments[index - 1]
        let currentRight = playback.segments[index]
        let proposed = origin + Double(translation / timelineWidth) * playback.duration
        let time = min(max(left.start + 0.001, proposed), currentRight.end - 0.001)
        guard playback.moveSharedBoundary(before: right.id, to: time, commit: commit) else { return }
        playback.seekForTimelineEdit(to: time, final: commit)
    }
}
