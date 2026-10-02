import AVKit
import SwiftUI

struct ContentView: View {
    @StateObject private var playback = PlaybackModel()
    @State private var confirmsTrim = false
    @State private var showsInspector = true
    private let refreshTimer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if playback.selectedSolveID == nil {
                SolveLibrary(playback: playback)
            } else {
                analyzer
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .onReceive(refreshTimer) { _ in playback.refresh() }
        .onDisappear { playback.player.pause() }
    }

    private var analyzer: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Library") { playback.showLibrary() }
                Text(playback.selectedSolve?.displayName ?? playback.filename ?? "Choose a local video to begin")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(playback.saveMessage?.hasPrefix("Could not save") == true ? "Save failed" : playback.isSaving ? "Saving…" : "Saved")
                    .font(.caption).foregroundStyle(.secondary)
                Menu {
                    Button("Import Video…", action: playback.chooseVideo).keyboardShortcut("o")
                    Button("Previous Solve") { playback.openAdjacentSolve(-1) }.disabled(playback.adjacentSolve(-1) == nil)
                    Button("Next Solve") { playback.openAdjacentSolve(1) }.disabled(playback.adjacentSolve(1) == nil)
                    Divider()
                    Button(showsInspector ? "Hide Inspector" : "Show Inspector") { showsInspector.toggle() }
                    if playback.canUndoTrim { Button("Undo Trim") { playback.undoTrim() } }
                    else { Button("Trim Video…") { confirmsTrim = true }.disabled(playback.trimRange == nil) }
                } label: { Image(systemName: "ellipsis").frame(width: 24) }
                Toggle("Overlay", isOn: $playback.showsAnalysisOverlay)
                    .toggleStyle(.switch)
                    .fixedSize()
                    .help("Show analysis overlay (⌘⇧H)")
            }
            HSplitView {
                VSplitView {
                    VStack(spacing: 8) {
                        AnalysisVideoView(playback: playback)
                            .frame(minHeight: 150, maxHeight: .infinity)
                        ControlBar(playback: playback)
                    }
                    .frame(minWidth: 430, minHeight: 200)
                    ReviewTimeline(playback: playback)
                        .frame(minHeight: 350, idealHeight: 370, maxHeight: 400)
                }
                if showsInspector {
                    AnalysisInspector(playback: playback)
                        .frame(minWidth: 280, idealWidth: 300, maxWidth: 340)
                        .background(.background.opacity(0.6))
                }
            }
            .frame(maxHeight: .infinity)
            if let message = playback.errorMessage ?? playback.saveMessage ?? playback.annotationMessage ?? playback.segmentMessage {
                Text(message)
                    .foregroundStyle(message.hasPrefix("Could not") || playback.errorMessage != nil ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let solve = playback.selectedSolve, !playback.videoExists(for: solve) {
                Button("Relink Video…") { playback.relinkVideo(for: solve) }
            }
        }
        .padding()
        .disabled(playback.isTrimming)
        .confirmationDialog("Trim video to the completed solve?", isPresented: $confirmsTrim) {
            Button("Trim Video") { Task { await playback.trimCompletedSolve() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Video before the first phase and after the final phase will be removed from the active copy. The original stays available for Undo until you quit Cubelyze, then is permanently deleted. Annotations outside the solve will also be removed.")
        }
    }
}

private struct SolveLibrary: View {
    @ObservedObject var playback: PlaybackModel
    @State private var query = ""
    @State private var filter = "All"
    private let filters = ["All", "Unreviewed", "In progress", "Complete", "Missing video"]

    private func status(_ solve: Solve) -> String {
        if solve.completedDuration != nil { return "Complete" }
        return solve.segments.isEmpty && solve.annotations.isEmpty && solve.pendingSegment == nil ? "Unreviewed" : "In progress"
    }
    private var filtered: [Solve] {
        playback.solves.filter { solve in
            (query.isEmpty || solve.filename.localizedStandardContains(query) || solve.scramble?.localizedStandardContains(query) == true)
                && (filter == "All" || (filter == "Missing video" ? !playback.videoExists(for: solve) : status(solve) == filter))
        }
    }
    private var days: [Date] {
        Array(Set(filtered.map { Calendar.current.startOfDay(for: $0.recordedAt) })).sorted(by: >)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Solve Library").font(.largeTitle).fontWeight(.semibold)
                Spacer()
                Button("Import Video…", action: playback.chooseVideo).keyboardShortcut("o")
            }
            HStack(spacing: 24) {
                Text("\(playback.solves.count) solves")
                Text("\(playback.completedSolveDurations.count) complete")
                if let best = playback.completedSolveDurations.min() {
                    Text("Best \(PlaybackModel.timestamp(best))")
                    Text("Mean \(PlaybackModel.timestamp(playback.completedSolveDurations.reduce(0, +) / Double(playback.completedSolveDurations.count)))")
                }
            }.foregroundStyle(.secondary)
            HStack {
                TextField("Search videos or scrambles", text: $query).textFieldStyle(.roundedBorder)
                Picker("Status", selection: $filter) {
                    ForEach(filters, id: \.self) { Text($0).tag($0) }
                }.frame(width: 240)
            }
            if let message = playback.importMessage ?? playback.errorMessage ?? playback.saveMessage {
                Text(message).foregroundStyle(.secondary)
            }
            if filtered.isEmpty {
                ContentUnavailableView(playback.solves.isEmpty ? "No solves yet" : "No matching solves",
                                       systemImage: "video", description: Text("Import a video or change your search and filter."))
            } else {
                List {
                    ForEach(days, id: \.self) { day in
                        Section(day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())) {
                            ForEach(filtered.filter { Calendar.current.isDate($0.recordedAt, inSameDayAs: day) }) { solve in
                                HStack(spacing: 14) {
                                    Button { playback.openSolve(solve) } label: {
                                        HStack(spacing: 14) {
                                            SolveThumbnail(playback: playback, solve: solve)
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(solve.displayName).font(.headline).lineLimit(1)
                                                Text("\(solve.recordedAt.formatted(date: .omitted, time: .shortened)) · \(solve.phaseTemplate.title)")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            VStack(alignment: .trailing, spacing: 5) {
                                                Text(solve.completedDuration.map(PlaybackModel.timestamp) ?? "—").monospacedDigit()
                                                Text(playback.videoExists(for: solve) ? status(solve) : "Video missing")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                        }.padding(.vertical, 6).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    if !playback.videoExists(for: solve) { Button("Relink…") { playback.relinkVideo(for: solve) } }
                                }
                            }
                        }
                    }
                }
            }
        }.padding()
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            Task { await playback.importVideos(files) }
            return true
        }
    }
}

private struct SolveThumbnail: View {
    @ObservedObject var playback: PlaybackModel
    let solve: Solve
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "video").frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary) }
        }.frame(width: 112, height: 64).clipped().clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: solve.videoPath) {
            let url = playback.thumbnailURL(for: solve)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 224, height: 128)
            if let result = try? await generator.image(at: CMTime(seconds: solve.segments.first?.start ?? 0, preferredTimescale: 600)) {
                image = NSImage(cgImage: result.image, size: .zero)
            }
        }
    }
}

private struct AnalysisVideoView: View {
    @ObservedObject var playback: PlaybackModel
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var dragOrigin: CGSize?

    var body: some View {
        GeometryReader { geometry in
            let videoWidth = min(geometry.size.width,
                                 geometry.size.height * playback.videoAspectRatio)
            let videoHeight = videoWidth / playback.videoAspectRatio
            ZStack {
                PlayerView(playback: playback)
                    .scaleEffect(zoom).offset(pan)
                    .gesture(DragGesture().onChanged { value in
                        guard zoom > 1 else { return }
                        if dragOrigin == nil { dragOrigin = pan }
                        let origin = dragOrigin ?? .zero
                        let limitX = geometry.size.width * (zoom - 1) / 2
                        let limitY = geometry.size.height * (zoom - 1) / 2
                        pan = CGSize(width: min(limitX, max(-limitX, origin.width + value.translation.width)),
                                     height: min(limitY, max(-limitY, origin.height + value.translation.height)))
                    }.onEnded { _ in dragOrigin = nil })
                if playback.showsAnalysisOverlay && playback.isReady {
                    AnalysisOverlay(playback: playback)
                        .frame(maxWidth: min(240, videoWidth * 0.4), alignment: .leading)
                        .padding(12)
                        .frame(width: videoWidth, height: videoHeight, alignment: .topLeading)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            .overlay(alignment: .bottomTrailing) {
                HStack {
                    Button("Fit") { zoom = 1; pan = .zero }
                    Button("−") { zoom = max(1, zoom - 0.5); pan = .zero }
                    Text("\(zoom, specifier: "%.1f")×").monospacedDigit()
                    Button("+") { zoom = min(4, zoom + 0.5) }
                }.padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(10)
            }
        }
        .onChange(of: playback.selectedSolveID) { _, _ in zoom = 1; pan = .zero }
    }
}

private struct AnalysisOverlay: View {
    @ObservedObject var playback: PlaybackModel

    private var hasContent: Bool {
        playback.overlaySegmentType != nil || !playback.overlayIntervals.isEmpty ||
        (playback.pendingAnnotation.map { $0.start <= playback.overlayTime } ?? false) ||
        !playback.overlayPointEvents.isEmpty
    }

    var body: some View {
        Group {
            if hasContent {
                VStack(alignment: .leading, spacing: 5) {
                    if let phase = playback.overlaySegmentType {
                        Text(phase.overlayTitle).font(.title3.weight(.semibold))
                        if let segment = playback.segments.first(where: { $0.start <= playback.overlayTime && playback.overlayTime < $0.end }) {
                            Text("\(playback.overlayTime - segment.start, specifier: "%.2f") / \(segment.duration, specifier: "%.2f")s")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        } else if let pending = playback.pendingSegment {
                            Text("\(playback.overlayTime - pending.start, specifier: "%.2f")s elapsed")
                                .font(.caption).monospacedDigit()
                        }
                    }
                    ForEach(playback.overlayIntervals) { annotation in
                        eventLine(annotation.category,
                                  elapsed: playback.overlayTime - annotation.timing.start)
                    }
                    if let pending = playback.pendingAnnotation,
                       pending.start <= playback.overlayTime {
                        eventLine(pending.category,
                                  elapsed: playback.overlayTime - pending.start)
                    }
                    ForEach(playback.overlayPointEvents) { annotation in
                        eventLine(annotation.category, elapsed: nil)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                }
                .shadow(radius: 5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func eventLine(_ category: AnnotationCategory, elapsed: Double?) -> some View {
        HStack(spacing: 6) {
            Circle().fill(category.color).frame(width: 6, height: 6)
            Text(category.title)
            if let elapsed {
                Text("· \(elapsed, specifier: "%.2f")s")
                    .monospacedDigit()
            }
        }
        .font(.caption)
    }
}

private struct AnalysisInspector: View {
    @ObservedObject var playback: PlaybackModel
    @State private var detailsExpanded = false
    @State private var tab = "Overview"
    @State private var requestedTemplate: SolveMethodTemplate?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Inspector").font(.headline)
                    Spacer()
                    if playback.selectedAnnotation != nil || playback.selectedSegment != nil {
                        Button("Done") { playback.clearSelection() }
                            .buttonStyle(.borderless)
                    }
                }
                Picker("Inspector view", selection: $tab) {
                    ForEach(["Overview", "Details", "Tags"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                if tab == "Overview" {
                    StatisticsDetails(playback: playback)
                } else if tab == "Details" {
                    if let annotation = playback.selectedAnnotation {
                        EventDetails(playback: playback, annotation: annotation)
                    } else if let segment = playback.selectedSegment {
                        SegmentDetails(playback: playback, segment: segment).id(segment.id)
                    } else {
                        ForEach(playback.segments) { segment in
                            Button { playback.selectSegment(segment) } label: {
                                InspectorValue(label: segment.type.title, value: PlaybackModel.timestamp(segment.duration))
                            }.buttonStyle(.plain)
                        }
                        Text("Select a phase or event to edit its timing and notes.").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let annotation = playback.selectedAnnotation {
                    AnnotationTagPicker(playback: playback, embedded: true, annotation: annotation)
                } else {
                    Text("Select an event to review its issue tags.").foregroundStyle(.secondary)
                    ForEach(playback.annotations) { event in
                        Button("\(event.category.title) · \(PlaybackModel.timestamp(event.timing.start))") {
                            playback.selectAnnotation(event)
                            tab = "Tags"
                        }.buttonStyle(.plain)
                    }
                }
                DisclosureGroup("Solve Details", isExpanded: $detailsExpanded) {
                    Picker("Method", selection: Binding(
                        get: { playback.phaseTemplate.id },
                        set: { id in
                            guard let template = SolveMethodTemplate.presets.first(where: { $0.id == id }),
                                  template != playback.phaseTemplate else { return }
                            if playback.segments.isEmpty && playback.pendingSegment == nil {
                                playback.updateMethodTemplate(template)
                            } else {
                                requestedTemplate = template
                            }
                        }
                    )) {
                        ForEach(SolveMethodTemplate.presets) { template in
                            Text(template.title).tag(template.id)
                        }
                        if !SolveMethodTemplate.presets.contains(where: { $0.id == playback.phaseTemplate.id }) {
                            Text(playback.phaseTemplate.title).tag(playback.phaseTemplate.id)
                        }
                    }
                    Text(playback.phaseTemplate.phases.map(\.title).joined(separator: " → "))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Scramble").font(.caption).foregroundStyle(.secondary)
                    TextField("Optional scramble", text: Binding(
                        get: { playback.selectedSolve?.scramble ?? "" },
                        set: playback.updateScramble
                    ), axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    Divider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .onChange(of: playback.selectedSegmentID) { _, id in if id != nil { tab = "Details" } }
        .onChange(of: playback.selectedAnnotationID) { _, id in if id != nil && tab != "Tags" { tab = "Details" } }
        .confirmationDialog("Change solve method?", isPresented: Binding(
            get: { requestedTemplate != nil },
            set: { if !$0 { requestedTemplate = nil } }
        )) {
            Button("Change Method and Clear Segments", role: .destructive) {
                if let requestedTemplate { playback.updateMethodTemplate(requestedTemplate) }
                requestedTemplate = nil
            }
            Button("Cancel", role: .cancel) { requestedTemplate = nil }
        } message: {
            Text("Changing the method clears existing phase timings and case labels. Annotations and the scramble are kept.")
        }
    }
}

private struct EventDetails: View {
    @ObservedObject var playback: PlaybackModel
    let annotation: VideoAnnotation
    @State private var edgeError: String?
    @State private var showsTagPicker = false

    private var note: Binding<String> {
        Binding(get: { playback.annotations.first(where: { $0.id == annotation.id })?.note ?? "" },
                set: { playback.updateAnnotationNote(id: annotation.id, note: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(annotation.category.title, systemImage: annotation.timing.end == nil ? "bookmark.fill" : "pause.fill")
                .font(.title3).fontWeight(.semibold).foregroundStyle(annotation.category.color)
            if let end = annotation.timing.end {
                InspectorValue(label: "Start", value: PlaybackModel.timestamp(annotation.timing.start))
                InspectorValue(label: "End", value: PlaybackModel.timestamp(end))
                InspectorValue(label: "Duration", value: PlaybackModel.timestamp(end - annotation.timing.start))
                HStack {
                    Button("Start ← playhead") { placeEdge(start: true) }
                    Button("End ← playhead") { placeEdge(start: false) }
                }
                .disabled(!playback.isReady)
                .controlSize(.small)
                if let edgeError { Text(edgeError).font(.caption).foregroundStyle(.red) }
            } else {
                InspectorValue(label: "Time", value: PlaybackModel.timestamp(annotation.timing.start))
            }
            HStack {
                Text("Issue tags").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Add Tags…") { showsTagPicker = true }
                    .popover(isPresented: $showsTagPicker) {
                        AnnotationTagPicker(playback: playback, annotation: annotation)
                    }
            }
            ForEach(annotation.tagIDs, id: \.self) { tagID in
                HStack(alignment: .top) {
                    Text(IssueTag.displayName(for: tagID)).font(.caption)
                    Spacer()
                    Button { playback.toggleAnnotationTag(id: annotation.id, tagID: tagID) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(IssueTag.displayName(for: tagID))")
                }
            }
            Text("Note").font(.caption).foregroundStyle(.secondary)
            TextField("Optional note", text: note, axis: .vertical)
                .lineLimit(3...6).textFieldStyle(.roundedBorder)
            Button("Delete Event", role: .destructive) { playback.deleteAnnotation(annotation) }
        }
    }

    private func placeEdge(start: Bool) {
        edgeError = playback.placeAnnotationEdgeAtPlayhead(id: annotation.id, startEdge: start)
            ? nil : "Step to a frame inside the valid range first."
    }
}

private struct AnnotationTagPicker: View {
    @ObservedObject var playback: PlaybackModel
    var embedded = false
    let annotation: VideoAnnotation
    @State private var query = ""
    @State private var focusedID: String?
    @FocusState private var searchFocused: Bool

    private var tags: [IssueTag] {
        IssueTag.matching(query, event: annotation.category, phase: playback.phaseForAnnotation(annotation))
    }
    private var categories: [String] {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ["Search results"] }
        return tags.reduce(into: []) { result, tag in
            if !result.contains(tag.category) { result.append(tag.category) }
        }
    }
    private var selectedIDs: [String] {
        playback.annotations.first { $0.id == annotation.id }?.tagIDs ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Issue tags · \(selectedIDs.count) selected").font(.headline)
            TextField("Search tags", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { toggleFocusedTag() }
            Text("Common tags for this event and phase appear first in each group.")
                .font(.caption).foregroundStyle(.secondary)
            if tags.isEmpty {
                Text("No matching tags.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $focusedID) {
                    ForEach(categories, id: \.self) { category in
                        Section(category) {
                            ForEach(tags.filter { category == "Search results" || $0.category == category }) { tag in
                                HStack {
                                    Image(systemName: selectedIDs.contains(tag.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selectedIDs.contains(tag.id) ? Color.accentColor : Color.secondary)
                                    Text(tag.name)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .tag(tag.id)
                                .onTapGesture {
                                    focusedID = tag.id
                                    playback.toggleAnnotationTag(id: annotation.id, tagID: tag.id)
                                }
                                .help(tag.description.isEmpty ? tag.name : tag.description)
                                .accessibilityLabel("\(tag.name), \(selectedIDs.contains(tag.id) ? "selected" : "not selected")")
                                .accessibilityElement(children: .ignore)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction {
                                    playback.toggleAnnotationTag(id: annotation.id, tagID: tag.id)
                                }
                            }
                        }
                    }
                }
                .onKeyPress(.return) { toggleFocusedTag(); return .handled }
                .onKeyPress(.space) { toggleFocusedTag(); return .handled }
            }
            HStack {
                Text("Return toggles a search result; use arrows in the list to browse.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(selectedIDs.contains(focusedID ?? "") ? "Remove" : "Add") { toggleFocusedTag() }
                    .disabled(tags.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: embedded ? 240 : 400, maxWidth: embedded ? .infinity : 400, minHeight: 440, maxHeight: 440)
        .onAppear { searchFocused = true; focusedID = tags.first?.id }
        .onChange(of: query) { _, _ in focusedID = tags.first?.id }
    }

    private func toggleFocusedTag() {
        guard let tagID = focusedID ?? tags.first?.id,
              tags.contains(where: { $0.id == tagID }) else { return }
        playback.toggleAnnotationTag(id: annotation.id, tagID: tagID)
    }
}

private struct SegmentDetails: View {
    @ObservedObject var playback: PlaybackModel
    let segment: SolveSegment
    @State private var startText = ""
    @State private var endText = ""
    @State private var caseText = ""
    @State private var error: String?
    @State private var confirmsDelete = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(segment.type.title, systemImage: "square.split.2x1").font(.title3).fontWeight(.semibold)
            InspectorValue(label: "Duration", value: PlaybackModel.timestamp(segment.duration))
            HStack { Text("Start (s)"); TextField("Start", text: $startText).textFieldStyle(.roundedBorder) }
            HStack {
                Button("Start ← playhead") { placeEdge(true) }
                Button("− frame") { step(true, -1) }
                Button("+ frame") { step(true, 1) }
            }.controlSize(.small)
            HStack { Text("End (s)"); TextField("End", text: $endText).textFieldStyle(.roundedBorder) }
            HStack {
                Button("End ← playhead") { placeEdge(false) }
                Button("− frame") { step(false, -1) }
                Button("+ frame") { step(false, 1) }
            }.controlSize(.small)
            TextField("Case label (optional)", text: $caseText).textFieldStyle(.roundedBorder)
            Button("Apply Changes") {
                guard let start = Double(startText), let end = Double(endText),
                      playback.updateSegment(segment, start: start, end: end, caseLabel: caseText) else {
                    error = "Keep boundaries inside the video and neighboring phases."; return
                }
                error = nil
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Button("Delete This and Later Phases…", role: .destructive) { confirmsDelete = true }
            Text("Boundary edits can be undone with ⌘Z.").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { resetFields() }
        .onChange(of: segment.start) { _, _ in resetFields() }
        .onChange(of: segment.end) { _, _ in resetFields() }
        .confirmationDialog("Delete this phase and all later phases?", isPresented: $confirmsDelete) {
            Button("Delete Phases", role: .destructive) { playback.deleteSegment(segment) }
        }
    }
    private func resetFields() {
        startText = String(format: "%.3f", segment.start)
        endText = String(format: "%.3f", segment.end)
        caseText = segment.caseLabel
    }
    private func placeEdge(_ start: Bool) {
        error = playback.placeSegmentEdgeAtPlayhead(id: segment.id, startEdge: start) ? nil : "Place the playhead inside a valid boundary range."
    }
    private func step(_ start: Bool, _ direction: Double) {
        Task {
            error = await playback.stepSegmentEdge(id: segment.id, startEdge: start, direction: direction)
                ? nil : "The boundary cannot move by a frame here."
        }
    }
}

private struct StatisticsDetails: View {
    @ObservedObject var playback: PlaybackModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Total solve").font(.caption).foregroundStyle(.secondary)
            Text(PlaybackModel.timestamp(playback.analyzedDuration))
                .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
            ForEach(Array(Set(playback.segments.map { $0.type.groupTitle })).sorted(), id: \.self) { group in
                let phases = playback.segments.filter { $0.type.groupTitle == group }
                HStack {
                    Circle().fill(phases.first?.type.color ?? .blue).frame(width: 7, height: 7)
                    InspectorValue(label: group, value: PlaybackModel.timestamp(phases.reduce(0) { $0 + $1.duration }))
                }
            }
            InspectorValue(label: "Pause time", value: PlaybackModel.timestamp(playback.totalPauseTime))
            InspectorValue(label: "Pauses", value: "\(playback.pauseAnnotations.count)")
            if let pause = playback.longestPause {
                Button { playback.selectAnnotation(pause) } label: {
                    InspectorValue(label: "Longest pause", value: PlaybackModel.timestamp(pause.timing.duration ?? 0))
                }.buttonStyle(.plain)
            }
            InspectorValue(label: "Rotations", value: "\(playback.eventCount(.rotation))")
            InspectorValue(label: "Regrips", value: "\(playback.eventCount(.regrip))")
            InspectorValue(label: "Other", value: "\(playback.eventCount(.other))")
        }
    }
}

private struct InspectorValue: View {
    let label: String
    let value: String
    var body: some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }
    }
}

private struct ControlBar: View {
    @ObservedObject var playback: PlaybackModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(playback.isPlaying ? "Pause" : "Play", action: playback.togglePlayback).help("Play / pause · Space")
                    Button("−1s") { playback.seek(by: -1) }.help("Back one second · ⇧←")
                    Button("◀︎") { playback.stepFrame(by: -1) }.help("Previous frame · ←")
                    Button("▶︎") { playback.stepFrame(by: 1) }.help("Next frame · →")
                    Button("+1s") { playback.seek(by: 1) }.help("Forward one second · ⇧→")
                    Picker("Speed", selection: Binding(get: { playback.speed }, set: playback.setSpeed)) {
                        Text("0.25×").tag(Float(0.25))
                        Text("0.5×").tag(Float(0.5))
                        Text("1×").tag(Float(1))
                        Text("2×").tag(Float(2))
                    }.labelsHidden().fixedSize()
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!playback.isReady)
    }
}

private struct ReviewTimeline: View {
    @ObservedObject var playback: PlaybackModel
    @State private var zoom: CGFloat = 1
    @State private var focusPlayhead = false

    private var displayedPosition: Double { playback.scrubPosition ?? playback.position }

    private func pointClusters(width: CGFloat) -> [[VideoAnnotation]] {
        let grouped = Dictionary(grouping: playback.annotations.filter { $0.timing.end == nil }) {
            Int(x($0.timing.start, width: width) / 20) * 10 + $0.category.rawValue
        }
        return grouped.keys.sorted().compactMap { grouped[$0] }
    }

    private func zoomToRange(_ start: Double?, _ end: Double?) {
        guard let start, let end, end > start else { return }
        zoom = min(32, max(1, CGFloat(playback.duration / (end - start))))
        playback.seek(to: start)
        focusPlayhead.toggle()
    }

    private var markingControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 12) {
                if playback.sequenceComplete {
                    Label("Solve complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Review Events") {
                        if let event = playback.annotations.first { playback.selectAnnotation(event) }
                        else { playback.clearSelection() }
                    }
                    Button("Next Solve") { playback.openAdjacentSolve(1) }
                        .disabled(playback.adjacentSolve(1) == nil)
                } else {
                    Button(playback.segmentActionTitle) { playback.markNextSegmentBoundary() }
                        .buttonStyle(.borderedProminent).help("Mark phase boundary · ⇧N")
                }
                Divider().frame(height: 22)
                ForEach([AnnotationCategory.pause, .rotation, .regrip], id: \.self) { category in
                    Button(category == .pause && playback.pendingAnnotation != nil ? "End Pause" : category.title) {
                        playback.addAnnotation(category)
                    }.help("\(category.title) · \(category.rawValue)")
                }
                Menu("More") {
                    Button("Other Event") { playback.addAnnotation(.other) }
                    Divider()
                    ForEach(playback.annotations) { event in
                        Button("\(event.category.title) · \(PlaybackModel.timestamp(event.timing.start))") { playback.selectAnnotation(event) }
                    }
                }
            }.controlSize(.small).disabled(!playback.isReady)
            }
            HStack {
                if let pending = playback.pendingSegment {
                    Text("\(pending.type.title) active from \(PlaybackModel.timestamp(pending.start))")
                    Button("Cancel Phase") { playback.cancelPendingSegment() }
                }
                if let pending = playback.pendingAnnotation {
                    Text("Pause open from \(PlaybackModel.timestamp(pending.start))")
                    Button("Cancel Pause") { playback.cancelPendingAnnotation() }
                }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private func x(_ time: Double, width: CGFloat) -> CGFloat {
        guard playback.duration > 0 else { return 0 }
        return width * min(1, max(0, time / playback.duration))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Timeline").font(.headline)
                Spacer()
                Button("Fit Video") { zoom = 1 }
                Button("Fit Solve") { zoomToRange(playback.segments.first?.start, playback.segments.last?.end) }
                    .disabled(playback.segments.isEmpty)
                Button("Fit Selection") {
                    if let segment = playback.selectedSegment { zoomToRange(segment.start, segment.end) }
                    else if let event = playback.selectedAnnotation { zoomToRange(event.timing.start, event.timing.end ?? event.timing.start + 2) }
                }.disabled(playback.selectedSegment == nil && playback.selectedAnnotation == nil)
                Button("−") { zoom = max(1, zoom / 2) }
                Button("+") { zoom = min(32, zoom * 2); focusPlayhead.toggle() }
            }.controlSize(.small)
            markingControls
            GeometryReader { geometry in
                let width = max(1, geometry.size.width * zoom)
                ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .leading) {
                        ForEach(0..<9) { tick in
                            Text(PlaybackModel.timestamp(playback.duration * Double(tick) / 8))
                                .font(.caption2).monospacedDigit()
                                .frame(width: 84, alignment: tick == 0 ? .leading : tick == 8 ? .trailing : .center)
                                .offset(x: width * CGFloat(tick) / 8 - (tick == 0 ? 0 : tick == 8 ? 84 : 42))
                        }
                    }.frame(width: width, height: 20, alignment: .leading)
                    Text("Phases")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.secondary.opacity(0.1))
                        ForEach(playback.segments) { segment in
                            let blockWidth = max(2, x(segment.end, width: width) - x(segment.start, width: width))
                            Button {
                                playback.selectSegment(segment)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    if blockWidth >= 48 { Text(segment.type.title).fontWeight(.medium) }
                                    if blockWidth >= 105 {
                                        Text(PlaybackModel.timestamp(segment.duration))
                                            .monospacedDigit()
                                    }
                                }
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .frame(width: blockWidth, height: 42, alignment: .leading)
                                .background(segment.type.color.opacity(playback.selectedSegmentID == segment.id ? 0.42 : 0.22))
                                .overlay(alignment: .leading) { Rectangle().fill(segment.type.color).frame(width: 1) }
                            }
                            .buttonStyle(.plain)
                            .help("\(segment.type.title): \(PlaybackModel.timestamp(segment.start))–\(PlaybackModel.timestamp(segment.end))")
                            .accessibilityLabel("\(segment.type.title), \(PlaybackModel.timestamp(segment.duration)); seek to start")
                            .offset(x: x(segment.start, width: width))
                        }
                        ForEach(playback.segments.dropFirst()) { segment in
                            TimelineSegmentBoundary(playback: playback, right: segment,
                                                    timelineWidth: width)
                                .offset(x: x(segment.start, width: width) - 9)
                        }
                        if let pending = playback.pendingSegment, displayedPosition > pending.start {
                            Text(pending.type.title)
                                .font(.caption)
                                .padding(.horizontal, 5)
                                .frame(width: max(2, x(displayedPosition, width: width) - x(pending.start, width: width)), height: 42, alignment: .leading)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .offset(x: x(pending.start, width: width))
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: width, height: 42)

                    Text("Events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.secondary.opacity(0.1))
                        ForEach(playback.annotations) { annotation in
                            if let end = annotation.timing.end {
                                let spanWidth = max(3, x(end, width: width) - x(annotation.timing.start, width: width))
                                TimelineIntervalBar(playback: playback, annotation: annotation,
                                                    spanWidth: spanWidth, timelineWidth: width)
                                .help("\(annotation.category.title): \(PlaybackModel.timestamp(annotation.timing.start))–\(PlaybackModel.timestamp(end))")
                                .offset(x: x(annotation.timing.start, width: width) - 9)
                            }
                        }
                    }
                    .frame(width: width, height: 38)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.secondary.opacity(0.1))
                        ForEach(pointClusters(width: width), id: \.first!.id) { cluster in
                            let event = cluster[0]
                            Group {
                                if cluster.count == 1 {
                                    Button { playback.selectAnnotation(event) } label: {
                                        Image(systemName: "bookmark.fill")
                                    }
                                } else {
                                    Menu("\(cluster.count)") {
                                        ForEach(cluster) { annotation in
                                            Button("\(annotation.category.title) · \(PlaybackModel.timestamp(annotation.timing.start))") {
                                                playback.selectAnnotation(annotation)
                                            }
                                        }
                                    }.menuStyle(.borderlessButton)
                                }
                            }
                            .font(.caption).frame(width: 20, height: 18)
                            .buttonStyle(.plain).foregroundStyle(event.category.color)
                            .help("\(cluster.count) \(event.category.title) event(s)")
                            .offset(x: min(width - 20, max(0, x(event.timing.start, width: width) - 10)),
                                    y: CGFloat(event.category.rawValue - 3) * 18)
                        }
                    }
                    .frame(width: width, height: 58)

                    Text("Playhead")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.secondary.opacity(0.25))
                            .frame(height: 8)
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: x(displayedPosition, width: width), height: 8)
                    }
                    .frame(width: width, height: 38)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                playback.scrub(to: min(1, max(0, value.location.x / width)) * playback.duration)
                            }
                            .onEnded { value in
                                playback.endScrubbing(at: min(1, max(0, value.location.x / width)) * playback.duration)
                            }
                    )
                }
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary)
                        .frame(width: 2, height: 218)
                        .id("playhead")
                        .offset(x: min(width - 3, max(0, x(displayedPosition, width: width) - 1.5)), y: 45)
                        .allowsHitTesting(false)
                }
                .frame(width: width)
                }
                .onChange(of: focusPlayhead) { _, _ in proxy.scrollTo("playhead", anchor: .center) }
                }
            }
            .frame(height: 270)
            .disabled(!playback.isReady || playback.duration <= 0)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Video timeline")
            .accessibilityValue("\(PlaybackModel.timestamp(displayedPosition)) of \(PlaybackModel.timestamp(playback.duration))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: playback.seek(by: 1)
                case .decrement: playback.seek(by: -1)
                @unknown default: break
                }
            }
            HStack {
                Text(PlaybackModel.timestamp(displayedPosition))
                    .accessibilityLabel("Current time")
                Spacer()
                Text(PlaybackModel.timestamp(playback.duration))
                    .accessibilityLabel("Total duration")
            }
            .font(.caption)
            .monospacedDigit()
        }
    }
}

private struct PlayerView: NSViewRepresentable {
    let playback: PlaybackModel

    func makeCoordinator() -> Coordinator { Coordinator(playback: playback) }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = playback.player
        context.coordinator.installKeyboardControls(for: view)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = playback.player
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.removeKeyboardControls()
    }

    @MainActor
    final class Coordinator {
        let playback: PlaybackModel
        private var keyMonitor: Any?

        init(playback: PlaybackModel) { self.playback = playback }

        func installKeyboardControls(for view: AVPlayerView) {
            // Handle review keys even when a button or speed picker has focus, but never in the file picker.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                guard let self, let window = view?.window, window.isKeyWindow,
                      event.window === window, window.attachedSheet == nil,
                      NSApp.modalWindow == nil,
                      !(window.firstResponder is NSTextView) else { return event }
                let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
                if modifiers == .shift, event.keyCode == 45 {
                    if !event.isARepeat { self.playback.markNextSegmentBoundary() }
                    return nil
                }
                if modifiers.isEmpty,
                   let characters = event.charactersIgnoringModifiers,
                   let number = Int(characters),
                   let category = AnnotationCategory(rawValue: number) {
                    if !event.isARepeat { self.playback.addAnnotation(category) }
                    return nil
                }
                switch (event.keyCode, modifiers) {
                case (4, [.command, .shift]):
                    if !event.isARepeat { self.playback.showsAnalysisOverlay.toggle() }
                case (49, []):
                    if !event.isARepeat { self.playback.togglePlayback() }
                case (123, []): self.playback.stepFrame(by: -1)
                case (124, []): self.playback.stepFrame(by: 1)
                case (123, .shift): self.playback.seek(by: -1)
                case (124, .shift): self.playback.seek(by: 1)
                default: return event
                }
                return nil
            }
        }

        func removeKeyboardControls() {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }
}
