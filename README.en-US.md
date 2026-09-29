# NovelAI Launcher Neo

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · English
</p>

This repository is a continuation of [Aaalice233/Aaalice_NAI_Launcher](https://github.com/Aaalice233/Aaalice_NAI_Launcher).

Maintained for **personal use only**.

## Update history

| Date | Version | Change | Preview |
| --- | --- | --- | --- |
| 2026-09-29 | 4.3.4 | Added "Export layered PSD" (desktop) to the storyboard toolbar's export menu: a page exports as one PSD with the background and every finished panel on its own layers, and panel layers carry a clipping mask, so the artwork can be re-framed by moving or scaling it in Photoshop or Krita while the visible result still matches the composited page PNG. |  |
| 2026-09-29 | 4.3.3 | Added a controllable comic-storyboard editor: lay out panels directly in the center workspace of the generation page, give each panel its own prompt, frame size, characters and seed; fully controllable irregular panels are supported — polygon frames with editable vertices and one-click irregular layouts such as banner-plus-split rows — with per-panel batch generation and composited page export; generation reuses the existing fixed-tag, Vibe and free-tier clamp pipelines, and the AI agent can read and write storyboards too. | <img src="docs/assets/storyboard-demo.jpg" width="480" alt="Storyboard editor demo"><br><img src="docs/assets/storyboard-demo-irregular.jpg" width="480" alt="Irregular panel layout demo"> |
| 2026-09-13 | 4.3.2 | Added an infinite canvas to the center of the generation page: image, seed to-do and Markdown note nodes can be dragged, resized and linked, canvases can be created and switched per project, and new results can land on the canvas automatically; fixed the AI TAG gallery source failing to load. |  |
| 2026-09-12 | 4.3.1 | Added a "Mode" choice (anime / furry) to the model section and a NovelAI image-generation style preset, and made theme switches reveal through a circular mask from the click position; fixed the style picker not opening and the missing thinking level for DeepSeek V4.1 Flash. |  |
| 2026-09-12 | 4.3.0 | Renamed to NovelAI-Launcher-Neo and moved to independent maintenance from upstream: new Android signing certificate and Windows install location, in-app updates pointing at this repository, and Google Drive / OneDrive cloud backup removed. |  |
