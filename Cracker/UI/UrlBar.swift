import SwiftUI

struct UrlBar: View {
    @Binding var value: String
    var resolving: Bool
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("치지직 링크를 붙여 넣기", text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .onSubmit(onSubmit)
            Button(action: onSubmit) {
                if resolving {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .buttonStyle(.plain)
            .frame(width: 36, height: 36)
            .background(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || resolving ? Color.primary.opacity(0.08) : Color.white)
            .foregroundStyle(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || resolving ? Color.secondary : Color.black)
            .clipShape(Circle())
            .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || resolving)
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
