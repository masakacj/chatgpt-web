import Foundation
import SafariServices

final class SafariWebExtensionHandler:
    NSObject,
    NSExtensionRequestHandling
{
    func beginRequest(
        with context: NSExtensionContext
    ) {
        let response =
            NSExtensionItem()

        if #available(iOS 15.0, *) {
            response.userInfo = [
                SFExtensionMessageKey: [
                    "ok": true
                ]
            ]
        }

        context.completeRequest(
            returningItems: [response],
            completionHandler: nil
        )
    }
}
