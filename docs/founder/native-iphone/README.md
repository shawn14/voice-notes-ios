# Native iPhone founder handoff — failing proof

On 2026-10-08, the real signed QA app on disposable iPhone 16 Pro / iOS 26.2 failed `ScreenshotTests/testFounderAgentBrief`. The test tapped the seeded Standup with Lena row; the resulting accessibility hierarchy still showed Home, and `prepareAgentBrief` was absent. This does not establish whether the row tap, navigation, or test targeting is at fault.

Evidence: [test summary](failed-test-summary.json) and [actual navigation log](failed-navigation.log). No phone brief/copy success is claimed. The iPad proof is separate and cannot establish iPhone behavior.

The disposable simulator and rebuildable output were removed at Shawn's request to recover disk space. Source, diagnostics, and the QA project remain. The standing test now retains a screenshot and complete accessibility hierarchy at this failure and stops before trying to operate an absent button. Its changed diagnostic path has not yet run.

Next: run the focused test using the established signed QA project when disk reserve permits, inspect the captured phone screen and hierarchy, identify the first failed navigation hop, and rerun the same test after the product fix. Never seed tests on Shawn's physical phone.
