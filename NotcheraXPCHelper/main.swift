import Foundation

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: (any NotcheraXPCHelperProtocol).self)

        let exportedObject = NotcheraXPCHelper()
        newConnection.exportedObject = exportedObject

        newConnection.resume()

        return true
    }
}

let delegate = ServiceDelegate()

/// Set up the one NSXPCListener for this service. It will handle all incoming connections.
let listener = NSXPCListener.service()
listener.delegate = delegate

listener.resume()
