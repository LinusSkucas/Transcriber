//
//  ContentView.swift
//  Transcript
//
//  Created by Linus Skucas on 7/28/23.
//

import SwiftUI
import Speech
import AVFoundation
import NaturalLanguage

struct SpeechView: View {
    @StateObject var speechEngine = SpeechEngine()
    
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    Button("Set up") {
                        speechEngine.requestPermissions()
                    }
                    Button("Start recording") {
                        speechEngine.transcribeText()
                    }
                    .disabled(!speechEngine.isAuthorized)
                    Button("Stop Recording") {
                        speechEngine.tearDown(with: "Stahhhp")
                    }
                    .disabled(!speechEngine.isRecording)
                    Spacer()
                }
                Section("Results") {
                    ScrollView {
                        Text(speechEngine.publishedText)
                    }
                }
                Spacer()
            }
            Divider()
//            ScrollViewReader { proxy in
                List(speechEngine.analysis) { analysis in
                    Text(analysis)
                        .tag(analysis)
                }
//            }
        }
        .padding()
    }
}

extension String: Identifiable {
    public var id: String {
        self + UUID().uuidString
    }
}

class SpeechEngine: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    @Published private(set) var publishedText: String = ""
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var denialReason: String = "Unknown"
    @Published private(set) var analysis = [String]()
    
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private lazy var request: SFSpeechAudioBufferRecognitionRequest = {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        return req
    }()
    private var task: SFSpeechRecognitionTask! = nil
    private var node: AVAudioInputNode? = nil
    
    var analysisTimer: Timer!
    
    override init() {
        super.init()
        if let speechTagger = recognizer {
            speechTagger.delegate = self
        }
    }
    
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { auth in
            DispatchQueue.main.async {
                switch auth {
                case .notDetermined:
                    self.denialReason = "Not determined."
                case .denied:
                    self.denialReason = "Denied."
                case .restricted:
                    self.denialReason = "Restricted."
                case .authorized:
                    self.denialReason = "Authorized"
                    self.isAuthorized = true
                @unknown default:
                    fatalError()
                }
            }
        }
    }
    
    func transcribeText() {
        do {
            self.isRecording = true
            try setupMicCapture()
            
            guard let audioNode = node,
                  let recognizer = recognizer else {
                tearDown(with: "Unable to start audio input.")
                return
            }
            
            let format = audioNode.outputFormat(forBus: 0)
            audioNode.installTap(onBus: 0,
                                 bufferSize: 1024,
                                 format: format) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
                self.request.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            // Begin capture
            task = recognizer.recognitionTask(with: request) { result, error in
                DispatchQueue.main.async {
                    var finished = false
                    
                    if let analyzedResult = result {
                        self.publishedText = analyzedResult.bestTranscription.formattedString
                        finished = analyzedResult.isFinal
                    }
                    
                    if error != nil || finished {
                        self.audioEngine.stop()
                        audioNode.removeTap(onBus: 0)
                        
                        var reason: String = "Finished."
                        if let issue = error {
                            reason = issue.localizedDescription
                        }
                        self.tearDown(with: reason)
                    }
                }
            }
            analysisTimer = Timer(fire: Date(), interval: 1, repeats: true, block: { [weak self] timer in
                self?.analyze()
            })
            RunLoop.current.add(analysisTimer, forMode: .default)
        } catch {
            tearDown(with: "Unable to begin mic capture.")
        }
    }
    
    func analyze() {
        print("analyzing")
        analysis = []
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = publishedText
        
        let options: NLTagger.Options = [.omitPunctuation, .omitPunctuation, .omitOther]
        let tags: [NLTag] = [.personalName, .placeName, .organizationName, .adjective, .adverb, .number, .noun]
        let forbiddenTags: [NLTag] = [.whitespace, .otherWhitespace, .other, .otherWord]
        
        tagger.enumerateTags(in: publishedText.startIndex..<publishedText.endIndex, unit: .word, scheme: .nameTypeOrLexicalClass, options: options) { tag, tokenRange in
            if let tag = tag, tags.contains(tag) {
                switch tag {
                case .personalName:
                    analysis.append("Person: \(publishedText[tokenRange])")
                case .placeName:
                    analysis.append("Place: \(publishedText[tokenRange])")
                case .organizationName:
                    analysis.append("Organization: \(publishedText[tokenRange])")
                case .adjective:
                    analysis.append("Adjective: \(publishedText[tokenRange])")
                case .adverb:
                    analysis.append("Adverb: \(publishedText[tokenRange])")
                case .number:
                    analysis.append("Number: \(publishedText[tokenRange])")
                case .noun:
                    analysis.append("Noun: \(publishedText[tokenRange])")
                default:
                    break
                }
            }
            
//            let (hypotheses, _) = tagger.tagHypotheses(at: tokenRange.lowerBound, unit: .word, scheme: .nameType, maximumCount: 1)
//                print(hypotheses)
            
            return true
        }
    }
    
    func tearDown(with reason: String) {
        self.denialReason = reason
        self.task = nil
        self.node = nil
        self.isRecording = false
        analysisTimer.invalidate()
    }
    
    // MARK: Private Functions
    
    private func setupMicCapture() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        node = audioEngine.inputNode
    }
    
    // MARK: Delegate
    
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            isAuthorized = false
            denialReason = "Unavailable."
        }
    }
}
