# Promo Materials Skill — Observations

This file records observations only. No skill is created in this release.

## Inputs required for every launch

- A runnable source-of-truth build
- Product name and exact version
- One-line product description
- Verified feature list
- Requirements and installation constraints
- Known issues
- Privacy boundaries
- Repository, release, and download URLs
- Real, privacy-safe visual assets
- Primary and secondary calls to action

## Rules that apply across channels

- Derive every claim from one shared fact source.
- Verify the release artifact before writing “available now.”
- Keep requirements and known issues consistent.
- Use one canonical repository and download link.
- Remove private names, paths, account details, and background-window content.
- Use isolated fictional Demo data rather than masking real data.
- Separate product facts from the platform-specific story.
- Never invent users, testimonials, adoption data, performance claims, or roadmap dates.

## Platform-specific rules

- **GitHub:** installation, requirements, privacy, known issues, build details, and release asset.
- **WeChat:** full first-person builder story with enough context for a reader unfamiliar with the project.
- **Xiaohongshu:** concrete daily scenario, visual sequence, concise cover copy, and restrained hashtags.
- **X:** one strong problem statement, a compact product description, and one direct link.
- **LinkedIn:** product judgment, implementation lessons, honest constraints, and professional feedback prompt.

## LitePark-specific facts that should not become generic rules

- ChatGPT Desktop must be running.
- LitePark uses conversation titles and visible sidebar accessibility elements.
- The shortcuts are `⌃⌥L` and `⌃⌥K`.
- The product uses a movable floating trigger.
- The current build is macOS only and not notarized.

## Steps suitable for future automation

- Compare installed-app and build-product hashes.
- Extract bundle name, version, minimum macOS version, and signing status.
- Scan text and image metadata for private paths and stale product names.
- Build a release ZIP and calculate checksums.
- Generate a platform-neutral source-of-truth file.
- Validate links and version strings across all documents.
- Create a release draft and upload assets.
- Produce a cross-channel privacy checklist.

