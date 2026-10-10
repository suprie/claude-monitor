import SwiftUI
import AppKit

struct MainWindowView: View {
    @State private var selection: MainNavigationItem? = .home

    var body: some View {
        NavigationSplitView {
            List(MainNavigationItem.allCases, selection: $selection) { item in
                NavigationLink(value: item) {
                    Label(item.title, systemImage: item.systemImage)
                }
            }
            .navigationTitle("Token Monitor")
            .listStyle(.sidebar)
        } detail: {
            switch selection ?? .home {
            case .home:
                HomeView()
            case .conversations:
                ConversationsView()
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

enum MainNavigationItem: String, CaseIterable, Hashable, Identifiable {
    case home
    case conversations

    var id: Self { self }

    var title: String {
        switch self {
        case .home: return "Home"
        case .conversations: return "Conversations"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "chart.bar.xaxis"
        case .conversations: return "bubble.left.and.bubble.right"
        }
    }
}

struct ConversationsView: View {
    var body: some View {
        ContentUnavailableView(
            "Conversations",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("Conversation history will appear here in a future phase.")
        )
        .navigationTitle("Conversations")
    }
}
