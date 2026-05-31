import SwiftUI

struct CreditsView: View {
    var body: some View {
        NavigationStack {
            List {

                LinkCreditCell(
                    name: "Tristannvm",
                    description: "Developer",
                    url: "https://github.com/Tristannvm"
                ) {
                    LinkCreditIcon(url: "https://github.com/Tristannvm.png")
                }

                LinkCreditCell(
                    name: "Capibarak",
                    description: "Animal",
                    url: "https://youtube.com/@Capibarakreal/"
                ) {
                    LinkCreditIcon(
                        url: "https://cdn.discordapp.com/avatars/1069242431880560660/bfa8d4076b64f01f5f060086e627f98d.png?size=4096"
                    )
                }
            }
            .navigationTitle("Credits")
        }
    }
}
