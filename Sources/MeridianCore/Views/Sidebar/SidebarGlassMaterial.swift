import SwiftUI

struct SidebarGlassMaterial<ClipShape: Shape>: View {
    let shape: ClipShape
    let tintColor: Color
    let settings: SidebarGlassSettings

    var body: some View {
        shape
            .fill(.clear)
            .glassEffect(
                .regular
                    .tint(tintColor.opacity(SidebarGlassRendering.glassTintOpacity(for: settings)))
                    .interactive(false),
                in: shape
            )
            .compositingGroup()
            .overlay {
                SidebarGlassTintOverlay(shape: shape, tintColor: tintColor, settings: settings)
            }
            .overlay {
                SidebarColorNoiseOverlay(
                    level: settings.colorNoiseLevel,
                    shape: shape
                )
            }
    }
}

private struct SidebarGlassTintOverlay<ClipShape: Shape>: View {
    let shape: ClipShape
    let tintColor: Color
    let settings: SidebarGlassSettings

    var body: some View {
        let recipe = SidebarGlassRendering.recipe(for: settings)

        ZStack {
            shape
                .fill(Color(nsColor: .windowBackgroundColor).opacity(recipe.neutralFillOpacity))

            shape
                .fill(tintColor.opacity(recipe.themeFillOpacity))

            LinearGradient(
                colors: [
                    .white.opacity(recipe.neutralHighlightOpacity),
                    tintColor.opacity(recipe.themeHighlightOpacity),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(shape)
        }
        .allowsHitTesting(false)
    }
}
