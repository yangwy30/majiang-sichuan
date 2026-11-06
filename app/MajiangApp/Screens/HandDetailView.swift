import SwiftUI
import MajiangKit

/// 「这一局」：账本里点开一局和牌。那手牌、和的是哪张、谁打的，番是怎么算的，谁付了多少；
/// 拍过照的还能看当时那张照片。要改就点右上角「改」，跟以前在账本里直接点开一样。
struct HandDetailView: View {
    @Environment(AppModel.self) private var model
    let gameID: UUID
    let recordID: UUID

    @State private var editing = false
    /// 改局页关掉以后才动账本，免得这一页在改局页底下先变了样。
    @State private var pendingChange: PendingChange?
    @State private var photo: UIImage?
    @State private var showPhoto = false
    @State private var editError: String?

    private enum PendingChange {
        case save(HandOutcome)
        case delete
    }

    var body: some View {
        Group {
            if let game = model.game(gameID), let index = game.records.firstIndex(where: { $0.id == recordID }),
               let win = game.records[index].win {
                content(game, record: game.records[index], win: win, number: index + 1)
            } else {
                ContentUnavailableView("这一局已经不在账本里了", systemImage: "tray")
            }
        }
        .page()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            NavBack("账本") { model.path.removeLast() }
            if model.game(gameID)?.records.contains(where: { $0.id == recordID }) == true {
                NavTool { Button("改") { editing = true } }
            }
        }
        .task(id: recordID) {
            photo = await HandPhotos.load(recordID)
            #if DEBUG
            if model.demoScreen == .handPhoto, photo != nil { showPhoto = true }
            #endif
        }
        .alert("没有改上", isPresented: Binding(get: { editError != nil }, set: { if !$0 { editError = nil } })) {
            Button("好") { editError = nil }
        } message: {
            Text(editError ?? "")
        }
    }

    private func content(_ game: Game, record: HandRecord, win: WinRecord, number: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("第 \(number) 局 · \(game.prevalentWind(ofHand: record.handIndex).name)场 · \(game.players[game.dealer(ofHand: record.handIndex)].name)坐庄")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
                    .padding(.top, 6)

                HStack(alignment: .firstTextBaseline) {
                    Text(win.isSelfDrawn ? "\(game.players[win.winner].name)自摸" : "\(game.players[win.winner].name)和")
                        .font(.system(size: 30, weight: .semibold))
                        .tracking(-0.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 12)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(win.totalFan)")
                            .font(.system(size: 46, weight: .ultraLight).monospacedDigit())
                            .tracking(-1)
                        Text("翻").font(Theme.serif(18))
                        Text("· \(win.fu) 符")
                            .font(.system(size: 16, weight: .light).monospacedDigit())
                            .foregroundStyle(Theme.gray)
                    }
                    .accessibilityElement(children: .combine)
                }
                .padding(.top, 2)

                if game.rules.paidFan(win) < win.totalFan {
                    Text("桌规封顶 \(game.rules.fanCap) 翻：\(win.totalFan) 翻按 \(game.rules.fanCap) 算")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.lineSoft, in: Capsule())
                        .padding(.top, 8)
                }

                if let hand = win.hand {
                    HandTiles(hand: hand)
                        .padding(.top, 22)
                    if let sentence = game.winSentence(win) {
                        Text(sentence)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.gray)
                            .padding(.top, 4)
                    }
                } else {
                    // 没拍照、在账本里直接改成「和了」的局，只有番数
                    Text(win.discarder.map { "\(game.players[$0].name)点的炮。" } ?? "自摸。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                        .padding(.top, 14)
                }

                if let photo {
                    Button { showPhoto = true } label: {
                        HStack {
                            Text("当时拍的照片").font(.system(size: 16))
                            Spacer()
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.faint)
                                .padding(.leading, 6)
                        }
                        .frame(minHeight: 64)
                        .overlay(alignment: .top) { Hairline() }
                        .overlay(alignment: .bottom) { Hairline() }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                    .accessibilityLabel("看当时拍的照片")
                }

                if win.fanOverride == nil && !win.fans.isEmpty && win.hand != nil {
                    SectionLabel("役种与宝牌")
                        .padding(.top, 26)
                        .padding(.bottom, 6)
                    FanList(win: win)
                } else {
                    Text("翻数是手填的，没有役种明细。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                        .padding(.top, 18)
                }

                SectionLabel("这局谁付多少")
                    .padding(.top, 24)
                    .padding(.bottom, 6)
                DeltaGrid(game: game, deltas: record.deltas)
                Text(game.paymentExplanation(win, deltas: record.deltas))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $editing, onDismiss: applyPendingChange) {
            EditHandSheet(game: game, record: record, number: number) { outcome in
                pendingChange = .save(outcome)
            } onDelete: {
                pendingChange = .delete
            }
        }
        .fullScreenCover(isPresented: $showPhoto) {
            if let photo {
                HandPhotoView(photo: photo, caption: "第 \(number) 局 · \(record.title(in: game))", date: record.date) {
                    HandPhotos.delete(recordID)
                    self.photo = nil
                }
            }
        }
    }

    /// 改成了别的结果（没人和、和错了）或者删掉了，这一页就没东西可看了，回账本。
    private func applyPendingChange() {
        guard let change = pendingChange, var game = model.game(gameID) else { return }
        pendingChange = nil
        switch change {
        case .save(let outcome):
            do {
                try game.replace(recordID, with: outcome)
                model.update(game)
            } catch let error as GameError {
                editError = error.message
                return
            } catch {
                editError = error.localizedDescription
                return
            }
            if case .win = outcome { return }
            model.path.removeLast()
        case .delete:
            game.remove(recordID)
            model.update(game)
            HandPhotos.delete(recordID)
            model.path.removeLast()
        }
    }
}

/// 当时拍的照片：深色底，整张放下。照片只存在这台手机上，可以删。
struct HandPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    var photo: UIImage
    var caption: String
    var date: Date
    var onDelete: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("关闭") { dismiss() }
                    .buttonStyle(NavButtonStyle(color: .white))
                Spacer()
                ShareLink(item: Image(uiImage: photo), preview: SharePreview(caption, image: Image(uiImage: photo))) {
                    Text("分享")
                }
                .buttonStyle(NavButtonStyle(color: .white.opacity(0.72), size: 16))
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("当时拍的照片")
            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text(caption)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("\(date.formatted(.dateTime.month().day().hour(.twoDigits(amPM: .omitted)).minute())) · 只存在这台手机上")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 24)
            Button("删掉这张照片") { confirmDelete = true }
                .buttonStyle(.text(Theme.faint))
                .padding(.top, 14)
                .padding(.bottom, 8)
        }
        .background(Theme.darkroom.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .confirmationDialog("删掉这张照片？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删掉", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("这一局的牌和分数都还在，只是不能再看照片。")
        }
    }
}
