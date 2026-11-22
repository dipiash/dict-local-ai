# UI design

Keep a single SwiftUI workspace and a non-activating recording HUD. AppRouter owns selected section and pending navigation. Preserve native menu shortcuts, keyboard focus and unsaved-edit confirmation. DesignTokens and AppStyle define common spacing, typography and geometry; reuse Shared/Components controls. Screen content must scroll within its bounds and not enlarge or displace the workspace/sidebar when long history is selected. Run the token checks and native UI acceptance for any layout change. The installer reuses the existing application icon and background.
