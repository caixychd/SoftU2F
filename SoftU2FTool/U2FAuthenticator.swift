//
//  U2FAuthenticator.swift
//  SoftU2FTool
//
//  Created by Benjamin P Toews on 1/25/17.
//  Copyright © 2017 GitHub. All rights reserved.
//

class U2FAuthenticator {
    static let shared = U2FAuthenticator()
    private static var hasShared = false

    private let u2fhid:U2FHID

    static func start() -> Bool {
        guard let ua:U2FAuthenticator = shared else { return false }
        return ua.start()
    }

    static func stop() -> Bool {
        guard let ua:U2FAuthenticator = shared else { return false }
        return ua.stop()
    }

    init?() {
        guard let uh:U2FHID = U2FHID.shared else { return nil }

        u2fhid = uh
        installMsgHandler()
    }

    func start() -> Bool {
        return u2fhid.run()
    }

    func stop() -> Bool {
        return u2fhid.stop()
    }

    func installMsgHandler() {
        u2fhid.handle(.Msg) { (_ msg:softu2f_hid_message) -> Bool in
            let data = msg.data.takeUnretainedValue() as Data
            print("Received message: \(data.base64EncodedString())")

            let cmd:APDUCommand

            do {
                cmd = try APDUCommand(raw: data)
            } catch let err {
                print("Error reading APDU command: \(err.localizedDescription)")
                return true
            }

            if let req = cmd.registerRequest {
                return self.handleRegisterRequest(req, cid: msg.cid)
            }

            if let req = cmd.authenticationRequest {
                return self.handleAuthenticationRequest(req, cid: msg.cid)
            }

            if let req = cmd.versionRequest {
                return self.handleVersionRequest(req, cid: msg.cid)
            }
            
            return false
        }
    }

    func handleRegisterRequest(_ req:RegisterRequest, cid:UInt32) -> Bool {
        print("Received register request!")

        let reg:U2FRegistration

        do {
            reg = try U2FRegistration(keyHandle: req.applicationParameter)
        } catch let err {
            print("Error creating registration: \(err.localizedDescription)")
            return false
        }

        let sigPayload = DataWriter()
        sigPayload.write(UInt8(0x00)) // reserved
        sigPayload.writeData(req.applicationParameter)
        sigPayload.writeData(req.challengeParameter)
        sigPayload.writeData(reg.keyHandle)
        sigPayload.writeData(reg.publicKey)
        let sig = reg.signWithCertificateKey(sigPayload.buffer)

        let resp = RegisterResponse(publicKey: reg.publicKey, keyHandle: reg.keyHandle, certificate: reg.certificate.toDer(), signature: sig)
        let respAPDU:APDUMessageProtocol

        do {
            respAPDU = try resp.apduWrapped()
        } catch let err {
            print("Error creating register response: \(err.localizedDescription)")
            return false
        }

        if u2fhid.sendMsg(cid: cid, data: respAPDU.raw) {
            print("Sent register response.")
            return true
        } else {
            print("Error sending register response.")
            return false
        }
    }

    func handleAuthenticationRequest(_ req:AuthenticationRequest, cid:UInt32) -> Bool {
        print("Received authentication request!")
        return true
    }

    func handleVersionRequest(_ req:VersionRequest, cid:UInt32) -> Bool {
        print("Received version request!")

        let resp = VersionResponse(version: "U2F_V2")
        let respAPDU:APDUMessageProtocol

        do {
            respAPDU = try resp.apduWrapped()
        } catch let err {
            print("Error creating version response: \(err.localizedDescription)")
            return false
        }

        if u2fhid.sendMsg(cid: cid, data: respAPDU.raw) {
            print("Sent version response.")
            return true
        } else {
            print("Error sending version response.")
            return false
        }
    }

    func sendError() {
    }
}