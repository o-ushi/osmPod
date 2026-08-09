import CoreTransferable

// ドラッグ&ドロップには String (feedURL) を直接使用するため未使用
struct ShowTransfer: Transferable {
    var feedURL: String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: \.feedURL,
            importing: { ShowTransfer(feedURL: $0) }
        )
    }
}
