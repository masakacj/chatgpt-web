import SwiftUI
import UIKit
import SafariServices

private let chatGPTURL =
    URL(string: "https://chatgpt.com/")!

private let scriptActionExtensionIdentifier =
    "com.masakacj.chatgptweb.scriptaction"

struct SafariContainerView:
    UIViewControllerRepresentable
{
    func makeUIViewController(
        context: Context
    ) -> SafariContainerLauncherViewController {
        SafariContainerLauncherViewController()
    }

    func updateUIViewController(
        _ uiViewController:
            SafariContainerLauncherViewController,
        context: Context
    ) {}
}

final class SafariContainerLauncherViewController:
    UIViewController,
    SFSafariViewControllerDelegate
{
    private weak var safariViewController:
        SFSafariViewController?

    private var presentingSafari = false

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor =
            .systemBackground

        SFSafariViewController
            .prewarmConnections(
                to: [chatGPTURL]
            )
    }

    override func viewDidAppear(
        _ animated: Bool
    ) {
        super.viewDidAppear(animated)
        presentSafariIfNeeded()
    }

    private func presentSafariIfNeeded() {
        guard
            !presentingSafari,
            safariViewController == nil,
            presentedViewController == nil
        else {
            return
        }

        presentingSafari = true

        let configuration =
            SFSafariViewController
                .Configuration()

        configuration
            .entersReaderIfAvailable = false

        configuration
            .barCollapsingEnabled = true

        if
            let image =
                UIImage(
                    systemName: "bolt.fill"
                )
        {
            configuration.activityButton =
                SFSafariViewController
                    .ActivityButton(
                        templateImage:
                            image,
                        extensionIdentifier:
                            scriptActionExtensionIdentifier
                    )
        }

        let safari =
            SFSafariViewController(
                url: chatGPTURL,
                configuration:
                    configuration
            )

        safari.delegate = self
        safari.dismissButtonStyle = .close
        safari.modalPresentationStyle =
            .fullScreen

        safariViewController = safari

        present(
            safari,
            animated: false
        ) { [weak self] in
            self?.presentingSafari = false
        }
    }

    func safariViewControllerDidFinish(
        _ controller:
            SFSafariViewController
    ) {
        safariViewController = nil

        DispatchQueue.main.async {
            [weak self] in
            self?.presentSafariIfNeeded()
        }
    }
}
