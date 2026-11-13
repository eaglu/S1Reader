import SwiftUI
import UIKit
import XCTest
@testable import S1Reader

/// Measures the contrast the quoted block actually draws.
///
/// The card owns its own fill, so it is the only place where the quoted text can
/// be checked against the surface it lands on: `.secondary` (label at 60%) reads
/// as ~3.5:1 on the light card, under the 4.5:1 floor this screen has to hold.
/// These tests resolve the real `Color` values the card uses, composite them the
/// way SwiftUI does (translucent fill over the row background, translucent text
/// over the fill) and apply the WCAG 2.1 relative-luminance formula.
final class QuoteStyleTests: XCTestCase {
    func testQuotedBodyMeetsTheContrastFloor() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ratio = contrast(of: QuoteStyle.body, on: card(style), style)
            print("QuoteStyle body \(name(style)) = \(String(format: "%.2f", ratio)):1")
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "quoted body on the \(name(style)) card")
        }
    }

    func testCaptionRowStaysReadable() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let ratio = contrast(of: QuoteStyle.header, on: card(style), style)
            print("QuoteStyle header \(name(style)) = \(String(format: "%.2f", ratio)):1")
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "quote caption on the \(name(style)) card")
        }
    }

    func testSecondaryWouldHaveMissedTheFloor() {
        // Why QuoteStyle.body is not simply `.secondary`.
        let ratio = contrast(of: .secondary, on: card(.light), .light)
        XCTAssertLessThan(ratio, 4.5)
    }

    func testCardFillIsFainterThanTheReplyBackground() {
        // The card is meant to sit one layer *below* the reply: a fill that reads
        // as a colour block is exactly what this redesign removes.
        for style in [UIUserInterfaceStyle.light, .dark] {
            let delta = abs(luminance(card(style)) - luminance(surface(style)))
            XCTAssertLessThan(delta, 0.1, "the \(name(style)) fill must stay subtle")
            XCTAssertGreaterThan(delta, 0, "the card still has to be visible")
        }
    }

    // MARK: - Colour plumbing

    private func name(_ style: UIUserInterfaceStyle) -> String {
        style == .dark ? "dark" : "light"
    }

    private func surface(_ style: UIUserInterfaceStyle) -> UIColor {
        resolve(Color(uiColor: .systemBackground), style)
    }

    /// The card fill as drawn: translucent fill composited over the row.
    private func card(_ style: UIUserInterfaceStyle) -> UIColor {
        over(resolve(QuoteStyle.fill, style), surface(style))
    }

    private func contrast(of color: Color, on background: UIColor, _ style: UIUserInterfaceStyle) -> CGFloat {
        let text = over(resolve(color, style), background)
        let lighter = max(luminance(text), luminance(background))
        let darker = min(luminance(text), luminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func resolve(_ color: Color, _ style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func over(_ top: UIColor, _ bottom: UIColor) -> UIColor {
        var topRed: CGFloat = 0, topGreen: CGFloat = 0, topBlue: CGFloat = 0, topAlpha: CGFloat = 0
        var lowRed: CGFloat = 0, lowGreen: CGFloat = 0, lowBlue: CGFloat = 0
        var lowAlpha: CGFloat = 0
        top.getRed(&topRed, green: &topGreen, blue: &topBlue, alpha: &topAlpha)
        bottom.getRed(&lowRed, green: &lowGreen, blue: &lowBlue, alpha: &lowAlpha)
        guard topAlpha < 1 else { return top }
        return UIColor(
            red: topRed * topAlpha + lowRed * (1 - topAlpha),
            green: topGreen * topAlpha + lowGreen * (1 - topAlpha),
            blue: topBlue * topAlpha + lowBlue * (1 - topAlpha),
            alpha: 1
        )
    }

    /// WCAG 2.1 relative luminance.
    private func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
