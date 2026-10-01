import Foundation
import UniformTypeIdentifiers

final class ActionRequestHandler:
    NSObject,
    NSExtensionRequestHandling
{
    func beginRequest(
        with context: NSExtensionContext
    ) {
        let extensionItem =
            NSExtensionItem()

        let finalizeArguments:
            NSDictionary = [
                NSExtensionJavaScriptFinalizeArgumentKey:
                    [
                        "inject": true
                    ] as NSDictionary
            ]

        let provider =
            NSItemProvider(
                item: finalizeArguments,
                typeIdentifier:
                    UTType
                        .propertyList
                        .identifier
            )

        extensionItem.attachments = [
            provider
        ]

        context.completeRequest(
            returningItems: [
                extensionItem
            ],
            completionHandler: nil
        )
    }
}
