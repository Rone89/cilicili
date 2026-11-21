import XCTest

@testable import bili

final class ArticleDetailTests: XCTestCase {
    func testArticleRouteParseSourceSupportsCVMobileCVOpusAndFallbackURL() throws {
        let cvURL = try XCTUnwrap(URL(string: "https://www.bilibili.com/read/cv34567890?spm_id_from=333"))
        XCTAssertEqual(ArticleRoute.parseSource(from: cvURL), .cv(id: 34567890))
        XCTAssertTrue(ArticleRoute(source: ArticleRoute.parseSource(from: cvURL), title: "t").supportsNativeReader)

        let mobileCVURL = try XCTUnwrap(URL(string: "https://www.bilibili.com/read/mobile/cv123456"))
        XCTAssertEqual(ArticleRoute.parseSource(from: mobileCVURL), .cv(id: 123456))

        let opusURL = try XCTUnwrap(URL(string: "https://www.bilibili.com/opus/987654321098765432"))
        XCTAssertEqual(ArticleRoute.parseSource(from: opusURL), .opus(id: "987654321098765432"))
        XCTAssertTrue(ArticleRoute(source: ArticleRoute.parseSource(from: opusURL), title: "t").supportsNativeReader)

        let webURL = try XCTUnwrap(URL(string: "https://www.bilibili.com/video/BV1xx411c7mD"))
        XCTAssertEqual(ArticleRoute.parseSource(from: webURL), .url(webURL))
        XCTAssertFalse(ArticleRoute(source: ArticleRoute.parseSource(from: webURL), title: "t").supportsNativeReader)
    }

    func testParseHTMLParsesHeadingsFormattingImagesBlockquotesListsCodeAndEntities() {
        let html = """
        <h1>主标题 &amp; 概览</h1>
        <p>第一段包含<strong>加粗</strong>、<em>斜体</em>、<del>删除</del>、<code>inline()</code>与<a href="https://www.bilibili.com/read/cv999">链接</a>&nbsp;文本。</p>
        <figure class="img-box"><img data-src="//i0.hdslb.com/bfs/article/sample.jpg" width="1200" height="800" /><figcaption>图注说明</figcaption></figure>
        <blockquote>引用内容 &quot;测试&quot;</blockquote>
        <ul><li>列表项一</li><li>列表项二</li></ul>
        <pre><code>let value = 42</code></pre>
        <hr />
        """

        let blocks = ArticleContentParser.parseHTML(html)
        XCTAssertEqual(blocks.count, 7)

        if case .heading(_, let level, let text) = blocks[0] {
            XCTAssertEqual(level, 1)
            XCTAssertEqual(text, "主标题 & 概览")
        } else {
            XCTFail("Expected heading block at index 0")
        }

        if case .paragraph(_, let runs, _) = blocks[1] {
            let joined = runs.map(\.text).joined()
            XCTAssertTrue(joined.contains("加粗"))
            XCTAssertTrue(joined.contains("inline()"))
            XCTAssertTrue(joined.contains("链接"))
            XCTAssertTrue(runs.contains(where: { $0.isBold && $0.text == "加粗" }))
            XCTAssertTrue(runs.contains(where: { $0.isItalic && $0.text == "斜体" }))
            XCTAssertTrue(runs.contains(where: { $0.isStrikethrough && $0.text == "删除" }))
            XCTAssertTrue(runs.contains(where: { $0.isCode && $0.text == "inline()" }))
            XCTAssertTrue(runs.contains(where: { $0.linkURL?.absoluteString == "https://www.bilibili.com/read/cv999" }))
        } else {
            XCTFail("Expected paragraph block at index 1")
        }

        if case .image(_, let url, let caption, let width, let height) = blocks[2] {
            XCTAssertEqual(url.absoluteString, "https://i0.hdslb.com/bfs/article/sample.jpg")
            XCTAssertEqual(caption, "图注说明")
            XCTAssertEqual(width, 1200)
            XCTAssertEqual(height, 800)
        } else {
            XCTFail("Expected image block at index 2")
        }

        if case .blockquote(_, let runs) = blocks[3] {
            XCTAssertEqual(runs.map(\.text).joined(), "引用内容 \"测试\"")
        } else {
            XCTFail("Expected blockquote block at index 3")
        }

        if case .list(_, let ordered, let items) = blocks[4] {
            XCTAssertFalse(ordered)
            XCTAssertEqual(items.map { $0.map(\.text).joined() }, ["列表项一", "列表项二"])
        } else {
            XCTFail("Expected list block at index 4")
        }

        if case .code(_, _, let text) = blocks[5] {
            XCTAssertEqual(text, "let value = 42")
        } else {
            XCTFail("Expected code block at index 5")
        }

        if case .divider = blocks[6] {
            // Expected divider
        } else {
            XCTFail("Expected divider block at index 6")
        }
    }

    func testParseOpusParagraphsDecodesTextPicAndDivider() throws {
        let json = """
        [
          {
            "para_type": 1,
            "align": 1,
            "text": {
              "nodes": [
                {
                  "type": "TEXT_NODE_TYPE_WORD",
                  "word": {
                    "words": "居中的加粗段落",
                    "style": { "bold": true }
                  }
                }
              ]
            }
          },
          {
            "para_type": 2,
            "pic": {
              "pics": [
                { "url": "//i0.hdslb.com/bfs/new_dyn/pic.png", "width": 800, "height": 600 }
              ]
            }
          },
          {
            "para_type": 3
          }
        ]
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let paragraphs = try JSONDecoder().decode([DynamicJSONValue].self, from: data)
        let blocks = ArticleContentParser.parseOpusParagraphs(paragraphs)

        XCTAssertEqual(blocks.count, 3)

        if case .paragraph(_, let runs, let alignment) = blocks[0] {
            XCTAssertEqual(alignment, .center)
            XCTAssertEqual(runs.first?.text, "居中的加粗段落")
            XCTAssertEqual(runs.first?.isBold, true)
        } else {
            XCTFail("Expected paragraph block")
        }

        if case .image(_, let url, _, let width, let height) = blocks[1] {
            XCTAssertEqual(url.absoluteString, "https://i0.hdslb.com/bfs/new_dyn/pic.png")
            XCTAssertEqual(width, 800)
            XCTAssertEqual(height, 600)
        } else {
            XCTFail("Expected image block")
        }

        if case .divider = blocks[2] {
            // Expected divider
        } else {
            XCTFail("Expected divider block")
        }
    }

    func testDynamicArticleBuildsCVRouteFromRawArticle() throws {
        let rawJSON = """
        {
          "id": 24680135,
          "title": "测试专栏标题",
          "desc": "摘要",
          "covers": ["//i0.hdslb.com/bfs/article/cover.jpg"]
        }
        """
        let data = try XCTUnwrap(rawJSON.data(using: .utf8))
        let value = try JSONDecoder().decode(DynamicJSONValue.self, from: data)
        let article = try XCTUnwrap(DynamicArticle(raw: value))
        let route = try XCTUnwrap(article.route())

        XCTAssertEqual(route.source, .cv(id: 24680135))
        XCTAssertEqual(route.title, "测试专栏标题")
        XCTAssertEqual(route.coverURL?.absoluteString, "https://i0.hdslb.com/bfs/article/cover.jpg")
    }

    func testDynamicFeedSupportsDetailNavigationForArticleWithoutTopLevelTextOrImages() {
        XCTAssertTrue(
            DynamicFeedCardDisplayModel.supportsDetailNavigation(
                hasTopLevelText: false,
                imageCount: 0,
                isForward: false,
                hasVideo: false,
                hasLive: false,
                hasPaidContent: false,
                hasArticle: true
            )
        )
    }
}
