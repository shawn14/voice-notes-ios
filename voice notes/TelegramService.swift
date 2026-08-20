//
//  TelegramService.swift
//  voice notes
//
//  Handles pairing with the Telegram door and syncing inbox items.
//  Thoughts sent via Telegram appear as Notes in the app.
//

import Foundation
import SwiftData
import UIKit

@Observable
class TelegramService {
    static let shared = TelegramService()
    
    // MARK: - Configuration
    
    /// Base URL for the door API (Vercel deployment)
    private let doorBaseURL = "https://eeon-door.vercel.app"
    
    /// Bot username for Telegram deep links
    private let botUsername = "heyeeon_bot"
    
    // MARK: - State
    
    /// Whether the user has initiated pairing (token generated)
    private(set) var isPairingInProgress = false
    
    /// Last sync timestamp
    private(set) var lastSyncAt: Date?
    
    /// Number of items synced in last sync
    private(set) var lastSyncCount = 0
    
    // MARK: - Pairing
    
    /// Generate a pairing token and open Telegram with the deep link.
    /// Call this when user taps "Message EEON".
    @MainActor
    func startPairing() async {
        guard let userId = AuthService.shared.userId else {
            print("[TelegramService] Cannot pair without signed-in user")
            return
        }
        
        isPairingInProgress = true
        
        do {
            let token = try await requestPairingToken(eeonUserId: userId)
            let telegramURL = URL(string: "https://t.me/\(botUsername)?start=\(token)")!
            
            // Open Telegram
            await UIApplication.shared.open(telegramURL)
            
            print("[TelegramService] Opened Telegram with pairing token")
        } catch {
            print("[TelegramService] Pairing failed: \(error)")
            isPairingInProgress = false
        }
    }
    
    /// Request a pairing token from the door API.
    private func requestPairingToken(eeonUserId: String) async throws -> String {
        let url = URL(string: "\(doorBaseURL)/api/pair?action=request")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["eeonUserId": eeonUserId]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TelegramError.pairingFailed
        }
        
        struct PairResponse: Codable {
            let token: String
            let telegramUrl: String
        }
        
        let result = try JSONDecoder().decode(PairResponse.self, from: data)
        return result.token
    }
    
    // MARK: - Inbox Sync
    
    /// Fetch inbox items from the door and convert to Notes.
    /// Call this on app foreground or after pairing.
    @MainActor
    func syncInbox(context: ModelContext) async {
        guard let userId = AuthService.shared.userId else {
            print("[TelegramService] Cannot sync without signed-in user")
            return
        }
        
        do {
            let items = try await fetchInbox(eeonUserId: userId)
            
            if items.isEmpty {
                print("[TelegramService] Inbox empty")
                return
            }
            
            // Convert inbox items to Notes
            var createdNotes: [Note] = []
            for item in items {
                let note = Note(
                    title: generateTitle(from: item.thought),
                    content: item.thought
                )
                note.sourceType = .telegram
                
                // Store the draft as the enhanced/rewritten version
                if let draft = item.draft {
                    note.enhancedNoteText = draft
                }
                
                // Store template info in annotation field
                if let templateName = item.templateName {
                    note.annotation = "Drafted as: \(templateName)"
                }
                
                context.insert(note)
                createdNotes.append(note)
            }
            
            try context.save()
            
            // Acknowledge the items
            let itemIds = items.map { $0.id }
            try await ackInboxItems(eeonUserId: userId, itemIds: itemIds)
            
            lastSyncAt = Date()
            lastSyncCount = createdNotes.count
            
            print("[TelegramService] Synced \(createdNotes.count) items from Telegram inbox")
            
            // Run extraction pipeline on new notes
            for note in createdNotes {
                Task {
                    await IntelligenceService.shared.processNoteSave(note: note, context: context)
                }
            }
            
        } catch {
            print("[TelegramService] Inbox sync failed: \(error)")
        }
    }
    
    /// Fetch inbox items from door API.
    private func fetchInbox(eeonUserId: String) async throws -> [InboxItem] {
        let encodedUserId = eeonUserId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? eeonUserId
        let url = URL(string: "\(doorBaseURL)/api/inbox?userId=\(encodedUserId)")!
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TelegramError.fetchFailed
        }
        
        struct InboxResponse: Codable {
            let items: [InboxItem]
        }
        
        let result = try JSONDecoder().decode(InboxResponse.self, from: data)
        return result.items
    }
    
    /// Acknowledge inbox items after successful sync.
    private func ackInboxItems(eeonUserId: String, itemIds: [String]) async throws {
        let url = URL(string: "\(doorBaseURL)/api/inbox?action=ack")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "eeonUserId": eeonUserId,
            "itemIds": itemIds
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TelegramError.ackFailed
        }
    }
    
    // MARK: - Helpers
    
    /// Generate a short title from the thought text.
    private func generateTitle(from thought: String) -> String {
        let words = thought.split(separator: " ").prefix(6)
        let title = words.joined(separator: " ")
        return title.count < thought.count ? "\(title)..." : thought
    }
    
    /// URL to open the bot directly (for already-paired users or landing).
    var telegramBotURL: URL {
        URL(string: "https://t.me/\(botUsername)")!
    }
}

// MARK: - Models

struct InboxItem: Codable {
    let id: String
    let thought: String
    let draft: String?
    let templateId: String?
    let templateName: String?
    let isVoice: Bool?
    let createdAt: Int64
}

// MARK: - Errors

enum TelegramError: LocalizedError {
    case pairingFailed
    case fetchFailed
    case ackFailed
    
    var errorDescription: String? {
        switch self {
        case .pairingFailed: return "Failed to connect to Telegram"
        case .fetchFailed: return "Failed to fetch messages"
        case .ackFailed: return "Failed to acknowledge messages"
        }
    }
}
