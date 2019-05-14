import Foundation
import func Evergreen.getLogger
import HAP
import NIOWebSocketClient
import NIO
import SwiftyJSON

let registerJson = """
    {
        "forcePairing": false,
        "pairingType": "PROMPT",
        "manifest": {
            "manifestVersion": 1,
            "appVersion": "1.1",
            "signed": {
                "created": "20140509",
                "appId": "com.lge.test",
                "vendorId": "com.lge",
                "localizedAppNames": {
                    "": "LG Remote App",
                    "ko-KR": "리모컨 앱",
                    "zxx-XX": "ЛГ Rэмotэ AПП"
                },
                "localizedVendorNames": {
                    "": "LG Electronics"
                },
                "permissions": [
                    "TEST_SECURE",
                    "CONTROL_INPUT_TEXT",
                    "CONTROL_MOUSE_AND_KEYBOARD",
                    "READ_INSTALLED_APPS",
                    "READ_LGE_SDX",
                    "READ_NOTIFICATIONS",
                    "SEARCH",
                    "WRITE_SETTINGS",
                    "WRITE_NOTIFICATION_ALERT",
                    "CONTROL_POWER",
                    "READ_CURRENT_CHANNEL",
                    "READ_RUNNING_APPS",
                    "READ_UPDATE_INFO",
                    "UPDATE_FROM_REMOTE_APP",
                    "READ_LGE_TV_INPUT_EVENTS",
                    "READ_TV_CURRENT_TIME"
                ],
                "serial": "2f930e2d2cfe083771f68e4fe7bb07"
            },
            "permissions": [
                "LAUNCH",
                "LAUNCH_WEBAPP",
                "APP_TO_APP",
                "CLOSE",
                "TEST_OPEN",
                "TEST_PROTECTED",
                "CONTROL_AUDIO",
                "CONTROL_DISPLAY",
                "CONTROL_INPUT_JOYSTICK",
                "CONTROL_INPUT_MEDIA_RECORDING",
                "CONTROL_INPUT_MEDIA_PLAYBACK",
                "CONTROL_INPUT_TV",
                "CONTROL_POWER",
                "READ_APP_STATUS",
                "READ_CURRENT_CHANNEL",
                "READ_INPUT_DEVICE_LIST",
                "READ_NETWORK_STATE",
                "READ_RUNNING_APPS",
                "READ_TV_CHANNEL_LIST",
                "WRITE_NOTIFICATION_TOAST",
                "READ_POWER_STATE",
                "READ_COUNTRY_INFO"
            ],
            "signatures": [
                {
                    "signatureVersion": 1,
                    "signature": "eyJhbGdvcml0aG0iOiJSU0EtU0hBMjU2Iiwia2V5SWQiOiJ0ZXN0LXNpZ25pbmctY2VydCIsInNpZ25hdHVyZVZlcnNpb24iOjF9.hrVRgjCwXVvE2OOSpDZ58hR+59aFNwYDyjQgKk3auukd7pcegmE2CzPCa0bJ0ZsRAcKkCTJrWo5iDzNhMBWRyaMOv5zWSrthlf7G128qvIlpMT0YNY+n/FaOHE73uLrS/g7swl3/qH/BGFG2Hu4RlL48eb3lLKqTt2xKHdCs6Cd4RMfJPYnzgvI4BNrFUKsjkcu+WD4OO2A27Pq1n50cMchmcaXadJhGrOqH5YmHdOCj5NSHzJYrsW0HPlpuAx/ECMeIZYDh6RMqaFM2DXzdKX9NmmyqzJ3o/0lkk/N97gfVRLW5hA29yeAwaCViZNCP8iC9aO0q9fQojoa7NQnAtw=="
                }
            ]
        }
    }
    """

struct Message: Codable {
    let type: String
    let id: String
    let payload: JSON?
    let uri: URL?

    init(type: String, id: String = UUID().uuidString, payload: JSON? = nil, uri: URL? = nil) {
        self.type = type
        self.id = id
        self.payload = payload
        self.uri = uri
    }
}

class CommandBuffer {
    let s: WebSocketClient.Socket

    private var promises = [String: EventLoopPromise<Message>]()

    init(_ s: WebSocketClient.Socket) {
        self.s = s
        s.onText { self.onText($1) }
    }

    func receiveNext(id: String) -> EventLoopFuture<Message> {
        let p = s.eventLoop.makePromise(of: Message.self)
        promises[id] = p
        return p.futureResult
    }

    func onText(_ string: String) {
        let d = string.data(using: .utf8)!
        let msg = try! JSONDecoder().decode(Message.self, from: d)
        if let p = promises.removeValue(forKey: msg.id) {
            p.succeed(msg)
        }
    }

    func send(_ msg: Message) -> EventLoopFuture<Message> {
        let p = receiveNext(id: msg.id)

        let j = try! JSONEncoder().encode(msg)
        let text = String(decoding: j, as: UTF8.self)
        s.send(text: text)

        return p
    }
}

extension Optional {
    enum Error: Swift.Error {
        case missingValue
    }
    func get() throws -> Wrapped {
        guard let s = self else { throw Error.missingValue }
        return s
    }
}

class WebOsTV {
    let loop = MultiThreadedEventLoopGroup(numberOfThreads: 4)
    let client: WebSocketClient

    enum State: Equatable {
        case initial
        case registered(key: String)
    }

    var state: State = .initial

    let host: String

    init(host: String) {
        self.host = host
        self.client = WebSocketClient(eventLoopGroupProvider: .shared(loop))
    }

    private var registerMessage: Message {
        var j = try! JSON(data: registerJson.data(using: .utf8)!)
        if case .registered(let s) = state {
            j["client-key"] = JSON(s)
        }
        return Message(type: "register", id: UUID().uuidString, payload: j, uri: nil)
    }

    func register() -> EventLoopFuture<String> {
        precondition(state == .initial, "already registered")

        let promise = loop.next().makePromise(of: String.self)
        let connect = client.connect(host: host, port: 3000) {
            let b = CommandBuffer($0)

            b.send(self.registerMessage).flatMap {
                switch $0.type {
                case "response" where $0.payload!["pairingType"] == "PROMPT":
                    return b.receiveNext(id: $0.id).flatMapThrowing {
                        defer { _ = b.s.close() }
                        let key = try $0.payload!["client-key"].string.get()
                        self.state = .registered(key: key)
                        return key
                    }
                case "registered":
                    defer { _ = b.s.close() }
                    let key = $0.payload!["client-key"].string!
                    self.state = .registered(key: key)
                    return b.s.eventLoop.makeSucceededFuture(key)
                default: fatalError("nope nope nope")
                }
            }.cascade(to: promise)
        }
        connect.whenFailure(promise.fail)
        return connect.flatMap {
            promise.futureResult
        }
    }

    func mouseSocket() -> EventLoopFuture<WebSocketClient.Socket> {
        let promise = loop.next().makePromise(of: WebSocketClient.Socket.self)
        let connect = client.connect(host: host, port: 3000) {
            let b = CommandBuffer($0)
            _ = b.send(self.registerMessage).flatMap { _ in
                b.send(Message(type: "request", uri: URL(string: "ssap://com.webos.service.networkinput/getPointerInputSocket")!))
            }.map { msg -> Void in
                defer { _ = b.s.close() }
                let path = msg.payload!["socketPath"].string!
                let url = URLComponents(string: path)!
                let connect2 = self.client.connect(host: url.host!, port: 3000, uri: url.path, headers: [:]) {
                    promise.succeed($0)
                }
                connect2.whenFailure(promise.fail)
            }
        }
        connect.whenFailure(promise.fail)
        return connect.flatMap {
            promise.futureResult
        }
    }
}

fileprivate let logger = getLogger("demo")

#if os(macOS)
    import Darwin
#elseif os(Linux)
    import Dispatch
    import Glibc
#endif

getLogger("hap").logLevel = .info
getLogger("hap.encryption").logLevel = .warning

struct State: Codable {
    var nightmodeEnabled: Bool
    var webosKey: String?
}

let stateUrl = URL(fileURLWithPath: "./state.json")
var state = (try? JSONDecoder().decode(State.self, from: Data(contentsOf: stateUrl))) ?? State(nightmodeEnabled: false, webosKey: nil)

func saveState() {
    try! JSONEncoder().encode(state).write(to: stateUrl)
}


let tv = WebOsTV(host: "192.168.2.112")
if let k = state.webosKey {
    tv.state = .registered(key: k)
} else {
    state.webosKey = try tv.register().wait()
    saveState()
}


let storage = FileStorage(filename: "configuration.json")
if CommandLine.arguments.contains("--recreate") {
    logger.info("Dropping all pairings, keys")
    try storage.write(Data())
}

let button = Accessory.Switch(
    info: Service.Info(name: "TV Night Mode", serialNumber: "42269")
)

button.switch.powerState.value = state.nightmodeEnabled

let device = Device(
    storage: storage,
    accessory: button
)

extension WebSocketClient.Socket {
    func asend(_ text: String) -> EventLoopFuture<Void> {
        let p = eventLoop.makePromise(of: Void.self)
        send(text: text, promise: p)
        return p.futureResult
    }
}

extension EventLoop {
    func delay(_ ms: Int) -> EventLoopFuture<Void> {
        let p = makePromise(of: Void.self)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
            p.succeed(())
        }
        return p.futureResult
    }
}
var pendingUpdate: Bool?
func tryUpdateNow() {
    print("trying update")
    guard let enable = pendingUpdate else { return }
    if enable == state.nightmodeEnabled {
        pendingUpdate = nil
        return
    }
    let direction = enable ? "LEFT" : "RIGHT"

    let f = tv.mouseSocket().flatMap { s in
        s.asend("type:button\nname:MENU\n\n").flatMap {
            s.eventLoop.delay(400)
        }.flatMap {
            s.asend("type:button\nname:DOWN\n\n")
        }.flatMap {
            s.eventLoop.delay(1300)
        }.flatMap {
            s.asend("type:button\nname:ENTER\n\n")
        }.flatMap {
            s.eventLoop.delay(50)
        }.flatMap {
            s.asend("type:button\nname:\(direction)\n\n")
        }.flatMap {
            s.eventLoop.delay(50)
        }.flatMap {
            s.asend("type:button\nname:BACK\n\n")
        }.flatMap {
            s.close()
        }
    }

    f.whenSuccess {
        print("updated successfully")
        pendingUpdate = nil
        state.nightmodeEnabled = enable
        saveState()
    }

    f.whenFailure {
        print("failed to update \($0)")
        updateRetrySource.schedule(deadline: .now() + .seconds(10))
    }
}

var updateRetrySource: DispatchSourceTimer = {
    let s = DispatchSource.makeTimerSource()

    s.setEventHandler {
        tryUpdateNow()
    }
    s.resume()
    return s
}()

func changeNightMode(_ enabled: Bool) -> Void {
    guard state.nightmodeEnabled != enabled else { return }
    print("setting night mode to \(enabled)")
    pendingUpdate = enabled

    tryUpdateNow()
}

class MyDeviceDelegate: DeviceDelegate {
    func characteristic<T>(_ characteristic: GenericCharacteristic<T>,
                           ofService service: Service,
                           ofAccessory accessory: Accessory,
                           didChangeValue newValue: T?) {
        let enable = newValue as! Bool
        changeNightMode(enable)
    }
}

var delegate = MyDeviceDelegate()
device.delegate = delegate
let server = try Server(device: device, listenPort: 0)

// Stop server on interrupt.
var keepRunning = true
func stop() {
    DispatchQueue.main.async {
        logger.info("Shutting down...")
        keepRunning = false
    }
}
signal(SIGINT) { _ in stop() }
signal(SIGTERM) { _ in stop() }

print("Initializing the server...")

print()
print("Scan the following QR code using your iPhone to pair this device:")
print()
print(device.setupQRCode.asText)
print()

withExtendedLifetime([delegate]) {
    if CommandLine.arguments.contains("--test") {
        print("Running runloop for 10 seconds...")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 10))
    } else {
        while keepRunning {
            RunLoop.current.run(mode: .default, before: Date.distantFuture)
        }
    }
}

try server.stop()
logger.info("Stopped")
