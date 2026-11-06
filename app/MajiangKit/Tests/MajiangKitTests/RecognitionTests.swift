import XCTest
@testable import MajiangKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class RecognitionTests: XCTestCase {
    private struct FixedKey: APIKeyProvider {
        func apiKey() throws -> String { "test-key" }
    }

    private final class FakeHTTP: HTTPClient, @unchecked Sendable {
        var requests: [URLRequest] = []
        var replies: [String]
        /// 不是 200 时原样返回 replies，不包成 Gemini 的回答。
        let status: Int
        init(replies: [String], status: Int = 200) { self.replies = replies; self.status = status }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let answer = replies.isEmpty ? "{}" : replies.removeFirst()
            if status != 200 { return (Data(answer.utf8), status) }
            let envelope: [String: Any] = ["candidates": [["content": ["parts": [["text": answer]]]]]]
            return (try JSONSerialization.data(withJSONObject: envelope), 200)
        }
    }

    func testGeminiParsesConcealedAndMelds() async throws {
        let http = FakeHTTP(replies: [#"{"concealed":["1m","2m","3m","5p","5p"],"melds":[{"kind":"pung","tiles":["东","东","东"]},{"kind":"concealed_kong","tiles":["9s","9s","9s","9s"]},{"kind":"chow","tiles":["4p","3p","2p"]}],"flowers":2}"#])
        let recognizer = GeminiRecognizer(configuration: GeminiConfiguration(endpoint: .direct(FixedKey())), http: http)
        let result = try await recognizer.recognize(RecognitionRequest(image: Data([0xFF, 0xD8])))
        XCTAssertEqual(result.concealed.map(\.tile), Tile.parseList("123m55p"))
        XCTAssertEqual(result.melds, [.pung(Tile(.honors, 1)), .kong(Tile(.bamboo, 9), concealed: true), .chow(Tile(.dots, 2))!])
        XCTAssertEqual(result.flowerCount, 2)

        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")
        XCTAssertTrue(request.url!.absoluteString.hasSuffix("models/gemini-3.8-flash:generateContent"))
        XCTAssertFalse(request.url!.absoluteString.contains("test-key"), "Key 不能出现在 URL 里")
    }

    func testThinkingLevelDefaultsToLow() throws {
        func thinking(_ config: GeminiConfiguration) -> Any? {
            let body = GeminiRecognizer(configuration: config).requestBody(for: RecognitionRequest(image: Data()))
            return (body["generationConfig"] as? [String: Any])?["thinkingConfig"]
        }
        let low = thinking(GeminiConfiguration(endpoint: .direct(FixedKey()))) as? [String: String]
        XCTAssertEqual(low, ["thinkingLevel": "low"])
        XCTAssertNil(thinking(GeminiConfiguration(endpoint: .direct(FixedKey()), thinkingLevel: nil)))
    }

    func testProxyRequestCarriesNoKey() throws {
        let config = GeminiConfiguration(endpoint: .proxy(url: URL(string: "https://example.com/recognize")!, token: "t", deviceID: "d"))
        let request = try GeminiRecognizer(configuration: config).makeURLRequest(for: RecognitionRequest(image: Data()))
        XCTAssertNil(request.value(forHTTPHeaderField: "x-goog-api-key"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Majiang-Device"), "d")
    }

    func testProxyRefusalShowsItsOwnMessage() async throws {
        let http = FakeHTTP(replies: [#"{"error":{"code":429,"message":"今天的次数用完了","majiang":true}}"#], status: 429)
        let gemini = GeminiRecognizer(configuration: GeminiConfiguration(endpoint: .proxy(url: URL(string: "https://example.com")!)), http: http)
        do {
            _ = try await gemini.recognize(RecognitionRequest(image: Data()))
            XCTFail("应该失败")
        } catch let error as RecognitionError {
            XCTAssertEqual(error.message, "今天的次数用完了")
        }
    }

    func testProxyRequestCarriesInviteCode() throws {
        let url = URL(string: "https://example.com/recognize")!
        let withCode = try GeminiRecognizer(configuration: GeminiConfiguration(endpoint: .proxy(url: url, deviceID: "d", inviteCode: "K7MPQ4")))
            .makeURLRequest(for: RecognitionRequest(image: Data()))
        XCTAssertEqual(withCode.value(forHTTPHeaderField: "X-Majiang-Invite"), "K7MPQ4")
        let without = try GeminiRecognizer(configuration: GeminiConfiguration(endpoint: .proxy(url: url, deviceID: "d")))
            .makeURLRequest(for: RecognitionRequest(image: Data()))
        XCTAssertNil(without.value(forHTTPHeaderField: "X-Majiang-Invite"))
    }

    func testInviteRefusalClearsCodeAndShowsMessage() async throws {
        let http = FakeHTTP(replies: [#"{"error":{"code":403,"message":"这个邀请码已经停用了","majiang":true,"invite":true}}"#], status: 403)
        let gemini = GeminiRecognizer(configuration: GeminiConfiguration(endpoint: .proxy(url: URL(string: "https://example.com")!)), http: http)
        let cleared = Flag()
        let guarded = InviteCheckedRecognizer(base: RuleCheckedRecognizer(base: gemini)) { await cleared.set() }
        do {
            _ = try await guarded.recognize(RecognitionRequest(image: Data()))
            XCTFail("应该失败")
        } catch let error as RecognitionError {
            XCTAssertEqual(error, .inviteRejected("这个邀请码已经停用了"))
            XCTAssertEqual(error.message, "这个邀请码已经停用了")
        }
        let wasCleared = await cleared.value
        XCTAssertTrue(wasCleared)
    }

    func testOtherRefusalsKeepTheCode() async throws {
        let http = FakeHTTP(replies: [#"{"error":{"code":429,"message":"这个邀请码今天的次数用完了","majiang":true}}"#], status: 429)
        let gemini = GeminiRecognizer(configuration: GeminiConfiguration(endpoint: .proxy(url: URL(string: "https://example.com")!)), http: http)
        let cleared = Flag()
        let guarded = InviteCheckedRecognizer(base: gemini) { await cleared.set() }
        do {
            _ = try await guarded.recognize(RecognitionRequest(image: Data()))
            XCTFail("应该失败")
        } catch let error as RecognitionError {
            XCTAssertEqual(error, .unavailable("这个邀请码今天的次数用完了"))
        }
        let wasCleared = await cleared.value
        XCTAssertFalse(wasCleared)
    }

    func testInviteCodeNormalize() {
        XCTAssertEqual(InviteCode.normalize(" k7m-pq4 "), "K7MPQ4")
        XCTAssertEqual(InviteCode.normalize("K7MPQ4"), "K7MPQ4")
        XCTAssertNil(InviteCode.normalize("K7MPQ"), "太短")
        XCTAssertNil(InviteCode.normalize("K7MPQ40"), "太长")
        XCTAssertNil(InviteCode.normalize("K7MPQO"), "O 不在字表里")
        XCTAssertNil(InviteCode.normalize("K1MPQ4"), "1 不在字表里")
        XCTAssertEqual(InviteCode.redeemURL(forProxy: URL(string: "https://relay.example.com/recognize")!).absoluteString,
                       "https://relay.example.com/invite")
    }

    func testRedeemInvite() async throws {
        let ok = FakeHTTP(replies: [#"{"ok":true,"code":"K7MPQ4","dailyLimit":50,"remaining":48}"#], status: 299)
        let proxy = URL(string: "https://relay.example.com/recognize")!
        // FakeHTTP 只在非 200 时原样返回，这里包一层把状态改成 200
        let redemption = try await InviteCode.redeem("k7mpq4", proxy: proxy, deviceID: "d", http: StatusOverride(base: ok, status: 200))
        XCTAssertEqual(redemption, InviteCode.Redemption(code: "K7MPQ4", dailyLimit: 50, remaining: 48))
        let sent = try XCTUnwrap(ok.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://relay.example.com/invite")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Majiang-Device"), "d")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: sent.httpBody!) as? [String: String], ["code": "K7MPQ4"])

        let bad = FakeHTTP(replies: [#"{"error":{"code":403,"message":"邀请码不对，核对一下再输","majiang":true,"invite":true}}"#], status: 403)
        do {
            _ = try await InviteCode.redeem("ZZZZZZ", proxy: proxy, deviceID: "d", http: bad)
            XCTFail("应该失败")
        } catch let error as RecognitionError {
            XCTAssertEqual(error, .inviteRejected("邀请码不对，核对一下再输"))
        }

        let unused = FakeHTTP(replies: [])
        do {
            _ = try await InviteCode.redeem("abc", proxy: proxy, deviceID: "d", http: unused)
            XCTFail("格式不对不该发请求")
        } catch let error as RecognitionError {
            guard case .inviteRejected = error else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(unused.requests.isEmpty)
    }

    private actor Flag {
        var value = false
        func set() { value = true }
    }

    private struct StatusOverride: HTTPClient {
        var base: HTTPClient
        var status: Int
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            (try await base.send(request).0, status)
        }
    }

    func testRuleCheckRetriesOnceWithFeedback() async throws {
        let bad = #"{"concealed":["1p","1p","1p","2p","2p","3p","3p","4p","4p","5p","4p","6p","6p","7p"],"melds":[],"flowers":0}"#
        let good = #"{"concealed":["1p","1p","1p","2p","2p","3p","3p","4p","4p","5p","5p","6p","6p","7p"],"melds":[],"flowers":0}"#
        let http = FakeHTTP(replies: [bad, good])
        let gemini = GeminiRecognizer(configuration: GeminiConfiguration(endpoint: .direct(FixedKey())), http: http)
        let result = try await RuleCheckedRecognizer(base: gemini).recognize(RecognitionRequest(image: Data()))
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertTrue(FanCalculator.isWinningShape(result.hand))

        let body = try JSONSerialization.jsonObject(with: http.requests[1].httpBody!) as! [String: Any]
        XCTAssertEqual((body["contents"] as! [Any]).count, 3, "第二次带上一轮回答和原因")
    }

    func testDualReadFlagsDisagreementsAndResolverPicksTheWinningOne() async throws {
        let a = Recognition(concealed: Tile.parseList("1112233445566p7p"), source: "端侧")
        var bTiles = Tile.parseList("1112233445566p7p")
        bTiles[9] = Tile(.dots, 4)
        let b = Recognition(concealed: bTiles, source: "Gemini")

        // 端侧读对，Gemini 读错一张
        let merged = DualReadRecognizer.merge(b, with: a)
        XCTAssertEqual(merged.reviewCount, 1)
        XCTAssertEqual(merged.concealed[9].candidates, [Tile(.dots, 4), Tile(.dots, 5)])

        let resolution = RecognitionResolver.resolve(merged, context: WinContext(selfDrawn: true))
        XCTAssertEqual(resolution.recommended[9], Tile(.dots, 5))
        XCTAssertTrue(resolution.result?.contains(.fullFlush) ?? false)

        // 两种读法都能和（5饼、6饼都成和）时不替用户挑
        var both = merged
        both.concealed[9].alternatives = [Tile(.dots, 6)]
        both.concealed[9].tile = Tile(.dots, 5)
        XCTAssertTrue(RecognitionResolver.resolve(both, context: WinContext()).recommended.isEmpty)

        // 端侧模型没装时只用 Gemini
        let dual = DualReadRecognizer(primary: OnDeviceRecognizer(), secondary: MockRecognizer(samples: [b], delay: .zero))
        let only = try await dual.recognize(RecognitionRequest(image: Data()))
        XCTAssertEqual(only.source, "Gemini")
    }

    func testMergeWithDifferentCounts() {
        let short = Recognition(concealed: Tile.parseList("123m456m789m11p23p"), source: "a")
        let long = Recognition(concealed: Tile.parseList("123m456m789m11p234p"), source: "b")
        // 另一路多读到一张：插在对应位置，标成待确认（可能是这一路漏读了）
        let merged = DualReadRecognizer.merge(short, with: long)
        XCTAssertEqual(merged.concealed.map(\.tile), Tile.parseList("123m456m789m11p234p"))
        XCTAssertEqual(merged.reviewCount, 1)
        XCTAssertTrue(merged.concealed[13].uncertain)
        // 这一路多读的一张也标出来
        let other = DualReadRecognizer.merge(long, with: short)
        XCTAssertEqual(other.concealed.count, 14)
        XCTAssertEqual(other.concealed.indices.filter { other.concealed[$0].needsReview }, [13])
    }

    func testMockSamplesAreConsistent() throws {
        let samples = MockRecognizer.defaultSamples
        XCTAssertTrue(samples.allSatisfy { $0.hand.hasValidTileCount })
        let flush = RecognitionResolver.resolve(samples[0], context: WinContext())
        XCTAssertNotNil(flush.result)
        XCTAssertTrue(try FanCalculator.score(samples[1].hand, context: WinContext()).get().meetsMinimum())
        XCTAssertFalse(FanCalculator.isWinningShape(samples[2].hand))
        XCTAssertFalse(WinAssistant.fixSuggestions(for: samples[2].hand, context: WinContext()).isEmpty)
    }
}
