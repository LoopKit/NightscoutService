//
//  RemoteCommandSourceV1.swift
//  NightscoutServiceKit
//
//  Created by Bill Gestrich on 2/25/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import OSLog

class RemoteCommandSourceV1: RemoteCommandSource {
    
    weak var delegate: RemoteCommandSourceV1Delegate?
    private let otpManager: OTPManager
    private let log = OSLog(category: "Remote Command Source V1")
    private var commandValidator: RemoteCommandValidator
    private var recentNotifications = RecentNotifications()
    
    init(otpManager: OTPManager) {
        self.otpManager = otpManager
        self.commandValidator = RemoteCommandValidator(otpManager: otpManager)
    }
    
    //MARK: RemoteCommandSource
    
    func remoteNotificationWasReceived(_ notification: [String: AnyObject]) async {
        
        if let encryptedReturnNotification = notification["encrypted_return_notification"] {
            log.info("Found encrypted_return_notification in notification: %{public}@", String(describing: encryptedReturnNotification))
        } else {
            log.info("No encrypted_return_notification found in notification. Available keys: %{public}@", Array(notification.keys).joined(separator: ", "))
        }
        
        do {
            guard let delegate = delegate else {return}
            let remoteNotification = try notification.toRemoteNotification()
            
            // Log after parsing to see if the field was preserved
            if let encryptedReturnNotification = remoteNotification.encryptedReturnNotification {
                log.info("Parsed encrypted_return_notification successfully, length: %d", encryptedReturnNotification.count)
            } else {
                log.info("encrypted_return_notification is nil after parsing")
            }
            
            guard await !recentNotifications.isDuplicate(remoteNotification) else {
                // Duplicate notifications are expected after app is force killed
                // https://github.com/LoopKit/Loop/issues/2174
                return
            }
            do {
                try commandValidator.validate(remoteNotification: remoteNotification)
            } catch {
                await delegate.commandSourceV1(self, validationError: error, remoteNotification: remoteNotification)
                throw error
            }
            try await delegate.commandSourceV1(self, handleAction: remoteNotification.toRemoteAction(), remoteNotification: remoteNotification)
        } catch {
            log.error("Remote Notification: %{public}@. Error: %{public}@", String(describing: notification), String(describing: error))
            try? await self.delegate?.commandSourceV1(self, uploadError: error, notification: notification)
        }
    }
}

protocol RemoteCommandSourceV1Delegate: AnyObject {
    func commandSourceV1(_: RemoteCommandSourceV1, handleAction action: Action, remoteNotification: RemoteNotification) async throws
    func commandSourceV1(_: RemoteCommandSourceV1, uploadError error: Error, notification: [String: AnyObject]) async throws
    /// Called when a command fails validation, before `uploadError`
    func commandSourceV1(_: RemoteCommandSourceV1, validationError error: Error, remoteNotification: RemoteNotification) async
}

private actor RecentNotifications {
    private var recentNotifications = [RemoteNotification]()
    
    func isDuplicate(_ remoteNotification: RemoteNotification) -> Bool {
        if recentNotifications.contains(where: {remoteNotification.id == $0.id}) {
            return true
        }
        recentNotifications.append(remoteNotification)
        return false
    }
}
