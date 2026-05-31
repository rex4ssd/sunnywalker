// SunnyWalker — ParentalGateView.swift  |  Day 6  |  parental gate (App Store Kids requirement)

import SwiftUI

// MARK: - GateQuestion

struct GateQuestion {
    let prompt: String
    let options: [String]
    let correct: String

    static func random() -> GateQuestion {
        let pool = allTemplates
        let template = pool[Int.random(in: 0..<pool.count)]
        return GateQuestion(
            prompt: template.prompt,
            options: template.options.shuffled(),
            correct: template.correct
        )
    }

    private static let allTemplates: [GateQuestion] = weekdayQuestions + largestNumberQuestions + multiplicationQuestions

    // MARK: Weekday-ordering questions (concept, not arithmetic)
    private static let weekdayQuestions: [GateQuestion] = [
        GateQuestion(
            prompt: "哪個選項的星期排列順序是正確的？",
            options: ["週一 → 週三 → 週五", "週三 → 週一 → 週五", "週五 → 週三 → 週一"],
            correct: "週一 → 週三 → 週五"
        ),
        GateQuestion(
            prompt: "哪個選項的星期排列順序是正確的？",
            options: ["週二 → 週四 → 週六", "週四 → 週二 → 週六", "週六 → 週四 → 週二"],
            correct: "週二 → 週四 → 週六"
        ),
        GateQuestion(
            prompt: "哪個選項的星期排列順序是正確的？",
            options: ["週日 → 週二 → 週四", "週二 → 週日 → 週四", "週四 → 週二 → 週日"],
            correct: "週日 → 週二 → 週四"
        ),
    ]

    // MARK: Largest 3-digit number
    private static let largestNumberQuestions: [GateQuestion] = [
        GateQuestion(
            prompt: "下面哪個數字最大？",
            options: ["932", "847", "578"],
            correct: "932"
        ),
        GateQuestion(
            prompt: "下面哪個數字最大？",
            options: ["763", "489", "651"],
            correct: "763"
        ),
        GateQuestion(
            prompt: "下面哪個數字最大？",
            options: ["819", "734", "296"],
            correct: "819"
        ),
    ]

    // MARK: 3-digit multiplication (adult-level)
    private static let multiplicationQuestions: [GateQuestion] = [
        GateQuestion(
            prompt: "127 × 4 = ？",
            options: ["508", "438", "612"],
            correct: "508"
        ),
        GateQuestion(
            prompt: "236 × 3 = ？",
            options: ["708", "596", "824"],
            correct: "708"
        ),
        GateQuestion(
            prompt: "154 × 5 = ？",
            options: ["770", "635", "912"],
            correct: "770"
        ),
    ]
}

// MARK: - ParentalGateView

struct ParentalGateView: View {
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var question = GateQuestion.random()
    @State private var wrongCount = 0
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        ZStack {
            GhibliColors.cloudWhite.ignoresSafeArea()
            VStack(spacing: 32) {
                header
                questionCard
                optionButtons
                Spacer()
                cancelButton
            }
            .padding(.horizontal, 28)
            .padding(.top, 48)
            .padding(.bottom, 32)
            .offset(x: shakeOffset)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 6) {
            Text("🔐")
                .font(.system(size: 48))
            Text("請大人來幫忙")
                .font(GhibliFonts.title(24))
                .foregroundStyle(GhibliColors.nightIndigo)
            Text("請回答以下問題才能繼續")
                .font(GhibliFonts.caption())
                .foregroundStyle(GhibliColors.totoroGray)
        }
    }

    private var questionCard: some View {
        WatercolorCard {
            Text(question.prompt)
                .font(GhibliFonts.title(20))
                .foregroundStyle(GhibliColors.nightIndigo)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
        }
    }

    private var optionButtons: some View {
        VStack(spacing: 12) {
            ForEach(question.options, id: \.self) { opt in
                GhibliButton(opt, color: GhibliColors.leafFresh) {
                    check(opt)
                }
            }
        }
    }

    private var cancelButton: some View {
        Button("取消") { dismiss() }
            .font(GhibliFonts.caption())
            .foregroundStyle(GhibliColors.totoroGray)
    }

    // MARK: - Logic

    private func check(_ answer: String) {
        if answer == question.correct {
            onSuccess()
            dismiss()
        } else {
            wrongCount += 1
            if wrongCount >= 3 {
                wrongCount = 0
                triggerShake()
            }
            question = GateQuestion.random()
        }
    }

    private func triggerShake() {
        let steps: [(CGFloat, Double)] = [
            (12, 0.00), (-12, 0.07), (10, 0.14), (-10, 0.21),
            (6, 0.28), (-6, 0.35), (0, 0.42)
        ]
        for (offset, delay) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.07)) {
                    shakeOffset = offset
                }
            }
        }
    }
}

#Preview {
    ParentalGateView(onSuccess: {})
}
