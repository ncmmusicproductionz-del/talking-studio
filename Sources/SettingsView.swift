import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput = ""
    @State private var region = "eastus"
    @State private var testing = false
    @State private var testResult: String? = nil
    @State private var testOK = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Settings").font(.system(size: 28, weight: .heavy, design: .rounded))
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Text("Done").font(.system(.headline, design: .rounded)).foregroundStyle(Theme.lightBlue)
                        }
                    }

                    CardSection(icon: "sparkles", title: "Natural AI voices",
                                subtitle: model.hasAzureKey ? "Connected to Azure Speech" : "Not set up yet") {
                        Text("Talking Studio uses Microsoft's official Azure Speech service: the same neural voices as the desktop studio (Andrew, Ryan, Connor and more). The free tier includes about 500,000 characters a month.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 8) {
                            stepRow(1, "Create a free account at portal.azure.com.")
                            stepRow(2, "Create a \"Speech service\" resource and choose the Free F0 tier.")
                            stepRow(3, "Open the resource, go to Keys and Endpoint, and copy KEY 1 and the Location/Region.")
                            stepRow(4, "Paste them below and press Save.")
                        }

                        if let link = URL(string: "https://portal.azure.com/#create/Microsoft.CognitiveServicesSpeechServices") {
                            Link(destination: link) {
                                Label("Open Azure portal", systemImage: "arrow.up.right.square")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            }
                            .tint(Theme.lightBlue)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Speech key").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                            SecureField(model.hasAzureKey ? "Saved (paste a new one to replace it)" : "Paste KEY 1 here", text: $keyInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.3)))
                        }

                        HStack {
                            Text("Region").font(.subheadline).foregroundStyle(Theme.secondary)
                            Spacer()
                            Picker("Region", selection: $region) {
                                ForEach(AzureSpeech.regions, id: \.self) { r in
                                    Text(r).tag(r)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.lightBlue)
                        }

                        HStack(spacing: 10) {
                            Button {
                                model.saveAzure(key: keyInput, region: region)
                                keyInput = ""
                                Haptics.success()
                                runTest()
                            } label: {
                                Label("Save & test", systemImage: "checkmark.seal")
                            }
                            .buttonStyle(PrimaryButtonStyle(enabled: !keyInput.isEmpty || model.hasAzureKey))
                            .disabled(keyInput.isEmpty && !model.hasAzureKey)

                            if model.hasAzureKey {
                                Button(role: .destructive) {
                                    model.clearAzureKey()
                                    testResult = nil
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .frame(maxWidth: 130)
                            }
                        }

                        if testing {
                            HStack(spacing: 8) {
                                ProgressView().tint(Theme.lightBlue)
                                Text("Testing the connection...").font(.footnote).foregroundStyle(Theme.secondary)
                            }
                        } else if let r = testResult {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: testOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle(testOK ? Theme.good : Theme.danger)
                                Text(r).font(.footnote).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Text("Your key is stored only on this iPhone, in the system Keychain. Script text is sent to Microsoft only when you make a video with an AI voice.")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CardSection(icon: "photo.on.rectangle.angled", title: "Pictures") {
                        Text("Background pictures come from Wikimedia Commons, NASA and the Cleveland Museum of Art. Only licences that allow commercial use and edits are used (CC0, public domain, CC BY). Credits are listed with each video. Check a picture's source page if you are unsure; logos and recognisable people may need extra permission.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CardSection(icon: "info.circle", title: "About") {
                        HStack {
                            Text("Version").foregroundStyle(Theme.secondary)
                            Spacer()
                            Text(appVersion).foregroundStyle(Color.white)
                        }
                        .font(.subheadline)
                        Text("Videos are saved in the Files app under On My iPhone > Talking Studio.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .padding(20)
            }
        }
        .onAppear { region = model.azureRegion }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return v + " (" + b + ")"
    }

    private func stepRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.blue.opacity(0.3)))
            Text(text).font(.footnote).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func runTest() {
        testing = true
        testResult = nil
        let r = region
        Task {
            let err = await model.testAzure(key: "", region: r)
            testing = false
            if let e = err {
                testOK = false
                testResult = e
                Haptics.error()
            } else {
                testOK = true
                testResult = "It works! The natural voices are ready."
                Haptics.success()
            }
        }
    }
}
