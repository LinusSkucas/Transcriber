//
//  ContentView.swift
//  Transcriber
//
//  Created by Linus Skucas on 7/30/23.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        SpeechView()
            .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
