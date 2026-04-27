(function () {
  const SETTINGS_KEY = "reader-mac-web-settings-v1";
  const PROGRESS_KEY = "reader-mac-web-progress-v1";

  const CHAPTER_PATTERNS = [
    /^第[\d一二三四五六七八九十百千零〇两]+[章节卷部篇回集]\s*.*$/,
    /^chapter\s+\d+.*$/i,
    /^section\s+\d+.*$/i,
    /^[\(\[]?\d+[\)\].、]\s+.+$/,
  ];

  const defaultSettings = {
    theme: "paper",
    fontSize: 20,
    lineHeight: 1.9,
    encoding: "auto",
  };

  const state = {
    mode: null,
    currentFile: null,
    currentBuffer: null,
    txt: null,
    epub: null,
    settings: loadJson(SETTINGS_KEY, defaultSettings),
    progress: loadJson(PROGRESS_KEY, {}),
  };

  const dom = {
    root: document.documentElement,
    fileInput: document.getElementById("file-input"),
    encodingSelect: document.getElementById("encoding-select"),
    themeSelect: document.getElementById("theme-select"),
    fontSizeRange: document.getElementById("font-size-range"),
    lineHeightRange: document.getElementById("line-height-range"),
    fontSizeValue: document.getElementById("font-size-value"),
    lineHeightValue: document.getElementById("line-height-value"),
    resetSettingsBtn: document.getElementById("reset-settings-btn"),
    fileMeta: document.getElementById("file-meta"),
    statusLine: document.getElementById("status-line"),
    tocCount: document.getElementById("toc-count"),
    tocList: document.getElementById("toc-list"),
    dropZone: document.getElementById("drop-zone"),
    emptyState: document.getElementById("empty-state"),
    txtView: document.getElementById("txt-view"),
    txtScroll: document.getElementById("txt-scroll"),
    txtContent: document.getElementById("txt-content"),
    txtPrevBtn: document.getElementById("txt-prev-btn"),
    txtNextBtn: document.getElementById("txt-next-btn"),
    txtProgress: document.getElementById("txt-progress"),
    epubView: document.getElementById("epub-view"),
    epubContainer: document.getElementById("epub-container"),
    epubPrevBtn: document.getElementById("epub-prev-btn"),
    epubNextBtn: document.getElementById("epub-next-btn"),
    epubProgress: document.getElementById("epub-progress"),
  };

  init();

  function init() {
    dom.themeSelect.value = state.settings.theme;
    dom.encodingSelect.value = state.settings.encoding;
    dom.fontSizeRange.value = String(state.settings.fontSize);
    dom.lineHeightRange.value = String(state.settings.lineHeight);

    applySettings();
    bindEvents();
  }

  function bindEvents() {
    dom.fileInput.addEventListener("change", async (event) => {
      const file = event.target.files && event.target.files[0];
      if (file) {
        await openFile(file);
      }
      event.target.value = "";
    });

    dom.themeSelect.addEventListener("change", () => {
      state.settings.theme = dom.themeSelect.value;
      persistSettings();
      applySettings();
    });

    dom.encodingSelect.addEventListener("change", async () => {
      state.settings.encoding = dom.encodingSelect.value;
      persistSettings();
      if (state.mode === "txt" && state.currentFile && state.currentBuffer) {
        await openTxtFromBuffer(state.currentFile, state.currentBuffer);
      }
    });

    dom.fontSizeRange.addEventListener("input", () => {
      state.settings.fontSize = Number(dom.fontSizeRange.value);
      persistSettings();
      applySettings();
    });

    dom.lineHeightRange.addEventListener("input", () => {
      state.settings.lineHeight = Number(dom.lineHeightRange.value);
      persistSettings();
      applySettings();
    });

    dom.resetSettingsBtn.addEventListener("click", () => {
      state.settings = { ...defaultSettings };
      dom.themeSelect.value = state.settings.theme;
      dom.encodingSelect.value = state.settings.encoding;
      dom.fontSizeRange.value = String(state.settings.fontSize);
      dom.lineHeightRange.value = String(state.settings.lineHeight);
      persistSettings();
      applySettings();
      if (state.mode === "txt" && state.currentFile && state.currentBuffer) {
        openTxtFromBuffer(state.currentFile, state.currentBuffer);
      }
      if (state.mode === "epub" && state.epub && state.epub.rendition) {
        applyEpubTheme();
      }
    });

    dom.txtPrevBtn.addEventListener("click", () => moveTxtChapter(-1));
    dom.txtNextBtn.addEventListener("click", () => moveTxtChapter(1));
    dom.epubPrevBtn.addEventListener("click", () => {
      if (state.epub && state.epub.rendition) {
        state.epub.rendition.prev();
      }
    });
    dom.epubNextBtn.addEventListener("click", () => {
      if (state.epub && state.epub.rendition) {
        state.epub.rendition.next();
      }
    });

    dom.txtScroll.addEventListener("scroll", throttle(() => {
      if (state.mode !== "txt" || !state.txt || !state.currentFile) {
        return;
      }

      const progress = ensureProgressRecord();
      progress.chapterIndex = state.txt.currentChapterIndex;
      progress.scrollTop = dom.txtScroll.scrollTop;
      persistProgress();
    }, 120));

    window.addEventListener("keydown", (event) => {
      if (state.mode === "txt") {
        if (event.key === "ArrowLeft") {
          moveTxtChapter(-1);
        }
        if (event.key === "ArrowRight") {
          moveTxtChapter(1);
        }
      } else if (state.mode === "epub" && state.epub && state.epub.rendition) {
        if (event.key === "ArrowLeft") {
          state.epub.rendition.prev();
        }
        if (event.key === "ArrowRight") {
          state.epub.rendition.next();
        }
      }
    });

    ["dragenter", "dragover"].forEach((type) => {
      dom.dropZone.addEventListener(type, (event) => {
        event.preventDefault();
        dom.dropZone.classList.add("is-dragging");
      });
    });

    ["dragleave", "dragend", "drop"].forEach((type) => {
      dom.dropZone.addEventListener(type, (event) => {
        event.preventDefault();
        dom.dropZone.classList.remove("is-dragging");
      });
    });

    dom.dropZone.addEventListener("drop", async (event) => {
      const file = event.dataTransfer && event.dataTransfer.files && event.dataTransfer.files[0];
      if (file) {
        await openFile(file);
      }
    });
  }

  async function openFile(file) {
    const extension = getFileExtension(file.name);
    const buffer = await file.arrayBuffer();
    state.currentFile = file;
    state.currentBuffer = buffer;
    updateFileMeta(file);

    if (extension === "epub") {
      await openEpub(file, buffer);
      return;
    }

    if (extension === "txt" || extension === "md" || extension === "text") {
      await openTxtFromBuffer(file, buffer);
      return;
    }

    showStatus(`暂不支持 .${extension || "unknown"}。当前 mac 版先覆盖 TXT / EPUB。`, true);
  }

  async function openTxtFromBuffer(file, buffer) {
    await teardownEpub();

    const encoding = pickEncoding(buffer, state.settings.encoding);
    const text = decodeText(buffer, encoding);
    const chapters = parseTxtChapters(text);

    state.mode = "txt";
    state.txt = {
      chapters,
      currentChapterIndex: 0,
      encoding,
    };

    dom.emptyState.classList.add("hidden");
    dom.epubView.classList.add("hidden");
    dom.txtView.classList.remove("hidden");

    showStatus(`已打开 TXT，编码：${encoding.toUpperCase()}，章节：${chapters.length}`);
    buildTxtToc(chapters);

    const progress = getProgressRecord();
    const chapterIndex = clamp(progress.chapterIndex ?? 0, 0, chapters.length - 1);
    renderTxtChapter(chapterIndex);

    requestAnimationFrame(() => {
      dom.txtScroll.scrollTop = progress.scrollTop ?? 0;
    });
  }

  async function openEpub(file, buffer) {
    await teardownEpub();

    state.mode = "epub";
    state.txt = null;

    dom.emptyState.classList.add("hidden");
    dom.txtView.classList.add("hidden");
    dom.epubView.classList.remove("hidden");
    dom.epubContainer.innerHTML = "";

    const book = ePub(buffer);
    const rendition = book.renderTo("epub-container", {
      width: "100%",
      height: "100%",
      flow: "scrolled-doc",
      manager: "continuous",
      allowScriptedContent: false,
    });

    state.epub = {
      book,
      rendition,
      toc: [],
    };

    applyEpubTheme();

    rendition.on("relocated", (location) => {
      updateEpubProgress(location);

      const progress = ensureProgressRecord();
      progress.location = location.start.cfi;
      progress.href = location.start.href || "";
      persistProgress();
    });

    const navigation = await book.loaded.navigation;
    const toc = flattenToc(navigation.toc || []);
    state.epub.toc = toc;
    buildEpubToc(toc);

    const progress = getProgressRecord();
    const initialLocation = progress.location || undefined;
    await rendition.display(initialLocation);

    showStatus(`已打开 EPUB，目录：${toc.length} 项`);
  }

  async function teardownEpub() {
    if (state.epub && state.epub.rendition) {
      try {
        state.epub.rendition.destroy();
      } catch (error) {
        console.warn(error);
      }
    }

    if (state.epub && state.epub.book) {
      try {
        state.epub.book.destroy();
      } catch (error) {
        console.warn(error);
      }
    }

    state.epub = null;
    dom.epubContainer.innerHTML = "";
  }

  function renderTxtChapter(index) {
    if (!state.txt) {
      return;
    }

    const chapter = state.txt.chapters[index];
    if (!chapter) {
      return;
    }

    state.txt.currentChapterIndex = index;
    const progress = ensureProgressRecord();
    progress.chapterIndex = index;
    progress.scrollTop = 0;
    persistProgress();

    const lines = chapter.content.split("\n");
    const html = [
      `<h2>${escapeHtml(chapter.title)}</h2>`,
      ...lines.map((line) => renderTxtParagraph(line)),
    ].join("");

    dom.txtContent.innerHTML = html;
    dom.txtPrevBtn.disabled = index <= 0;
    dom.txtNextBtn.disabled = index >= state.txt.chapters.length - 1;
    dom.txtProgress.textContent = `第 ${index + 1} / ${state.txt.chapters.length} 章`;

    syncActiveToc(index);
    dom.txtScroll.scrollTop = 0;
  }

  function moveTxtChapter(delta) {
    if (!state.txt) {
      return;
    }

    const nextIndex = clamp(
      state.txt.currentChapterIndex + delta,
      0,
      state.txt.chapters.length - 1,
    );

    if (nextIndex !== state.txt.currentChapterIndex) {
      renderTxtChapter(nextIndex);
    }
  }

  function buildTxtToc(chapters) {
    dom.tocCount.textContent = String(chapters.length);
    dom.tocList.innerHTML = "";

    chapters.forEach((chapter, index) => {
      const button = document.createElement("button");
      button.className = "toc-item";
      button.type = "button";
      button.dataset.index = String(index);
      button.innerHTML = `${escapeHtml(chapter.title)}<small>TXT 章节</small>`;
      button.addEventListener("click", () => renderTxtChapter(index));
      dom.tocList.appendChild(button);
    });
  }

  function buildEpubToc(toc) {
    dom.tocCount.textContent = String(toc.length);
    dom.tocList.innerHTML = "";

    toc.forEach((item, index) => {
      const button = document.createElement("button");
      button.className = "toc-item";
      button.type = "button";
      button.dataset.href = item.href;
      button.dataset.index = String(index);
      button.innerHTML = `${escapeHtml(item.label || `Chapter ${index + 1}`)}<small>EPUB 目录</small>`;
      button.addEventListener("click", () => {
        if (state.epub && state.epub.rendition) {
          state.epub.rendition.display(item.href);
        }
      });
      dom.tocList.appendChild(button);
    });
  }

  function updateEpubProgress(location) {
    const currentHref = normalizeHref(location.start.href || "");
    const tocIndex = state.epub
      ? state.epub.toc.findIndex((item) => normalizeHref(item.href) === currentHref)
      : -1;

    if (tocIndex >= 0) {
      syncActiveToc(tocIndex);
      const currentItem = state.epub.toc[tocIndex];
      dom.epubProgress.textContent = currentItem.label || `目录 ${tocIndex + 1}`;
    } else {
      dom.epubProgress.textContent = "EPUB 阅读中";
    }
  }

  function syncActiveToc(index) {
    [...dom.tocList.querySelectorAll(".toc-item")].forEach((element) => {
      element.classList.toggle("is-active", Number(element.dataset.index) === index);
    });
  }

  function applySettings() {
    dom.root.dataset.theme = state.settings.theme;
    dom.root.style.setProperty("--reader-font-size", `${state.settings.fontSize}px`);
    dom.root.style.setProperty("--reader-line-height", String(state.settings.lineHeight));
    dom.fontSizeValue.textContent = `${state.settings.fontSize}px`;
    dom.lineHeightValue.textContent = state.settings.lineHeight.toFixed(1);

    if (state.epub && state.epub.rendition) {
      applyEpubTheme();
    }
  }

  function applyEpubTheme() {
    if (!state.epub || !state.epub.rendition) {
      return;
    }

    const styles = getThemeStyles();
    state.epub.rendition.themes.register("reader-mac-theme", {
      body: {
        background: styles.background,
        color: styles.text,
        "font-size": `${state.settings.fontSize}px`,
        "line-height": String(state.settings.lineHeight),
        "font-family": '"Iowan Old Style", "Palatino Linotype", "PingFang SC", serif',
        padding: "14px 18px 40px",
      },
      p: {
        "text-indent": "2em",
        margin: "0 0 1em",
      },
      h1: {
        color: styles.text,
      },
      h2: {
        color: styles.text,
      },
      h3: {
        color: styles.text,
      },
      a: {
        color: styles.accent,
      },
    });
    state.epub.rendition.themes.select("reader-mac-theme");
  }

  function getThemeStyles() {
    const computed = getComputedStyle(dom.root);
    return {
      background: computed.getPropertyValue("--surface-strong").trim(),
      text: computed.getPropertyValue("--text").trim(),
      accent: computed.getPropertyValue("--accent").trim(),
    };
  }

  function updateFileMeta(file) {
    const extension = getFileExtension(file.name).toUpperCase() || "UNKNOWN";
    const size = formatBytes(file.size);
    dom.fileMeta.innerHTML =
      `<strong>${escapeHtml(file.name)}</strong><br>${extension} · ${size}<br>` +
      `标识：${escapeHtml(getFileFingerprint(file))}`;
  }

  function showStatus(message, isError) {
    dom.statusLine.textContent = message;
    dom.statusLine.style.color = isError ? "#c84b31" : "";
  }

  function getProgressRecord() {
    if (!state.currentFile) {
      return {};
    }

    return state.progress[getFileFingerprint(state.currentFile)] || {};
  }

  function ensureProgressRecord() {
    const key = getFileFingerprint(state.currentFile);
    if (!state.progress[key]) {
      state.progress[key] = {};
    }
    return state.progress[key];
  }

  function persistSettings() {
    localStorage.setItem(SETTINGS_KEY, JSON.stringify(state.settings));
  }

  function persistProgress() {
    localStorage.setItem(PROGRESS_KEY, JSON.stringify(state.progress));
  }

  function parseTxtChapters(text) {
    const normalized = text.replace(/\r\n?/g, "\n");
    const lines = normalized.split("\n");
    const chapters = [];
    let currentTitle = "开始阅读";
    let currentLines = [];

    lines.forEach((line) => {
      const trimmed = line.trim();
      if (isChapterHeading(trimmed) && currentLines.length > 0) {
        chapters.push({
          title: currentTitle,
          content: currentLines.join("\n").trim(),
        });
        currentTitle = trimmed;
        currentLines = [trimmed];
      } else {
        if (currentLines.length === 0 && trimmed) {
          currentTitle = currentTitle === "开始阅读" ? trimmed.slice(0, 28) : currentTitle;
        }
        currentLines.push(line);
      }
    });

    if (currentLines.length > 0) {
      chapters.push({
        title: currentTitle,
        content: currentLines.join("\n").trim(),
      });
    }

    const cleaned = chapters
      .map((chapter, index) => ({
        title: chapter.title || `章节 ${index + 1}`,
        content: chapter.content || "",
      }))
      .filter((chapter) => chapter.content.length > 0);

    return cleaned.length > 0
      ? cleaned
      : [{ title: "全文", content: normalized.trim() }];
  }

  function isChapterHeading(text) {
    if (!text || text.length > 60) {
      return false;
    }
    return CHAPTER_PATTERNS.some((pattern) => pattern.test(text));
  }

  function renderTxtParagraph(line) {
    const trimmed = line.trim();
    if (!trimmed) {
      return '<p class="is-empty"></p>';
    }
    if (isChapterHeading(trimmed)) {
      return `<p class="is-heading">${escapeHtml(trimmed)}</p>`;
    }
    return `<p>${escapeHtml(trimmed)}</p>`;
  }

  function flattenToc(items, result = []) {
    items.forEach((item) => {
      result.push({
        label: item.label || "Untitled",
        href: item.href || item.id || "",
      });
      if (item.subitems && item.subitems.length > 0) {
        flattenToc(item.subitems, result);
      }
    });
    return result;
  }

  function pickEncoding(buffer, preferred) {
    if (preferred && preferred !== "auto") {
      return preferred;
    }

    const view = new Uint8Array(buffer);
    if (view.length >= 3 && view[0] === 0xef && view[1] === 0xbb && view[2] === 0xbf) {
      return "utf-8";
    }
    if (view.length >= 2 && view[0] === 0xff && view[1] === 0xfe) {
      return "utf-16le";
    }
    if (view.length >= 2 && view[0] === 0xfe && view[1] === 0xff) {
      return "utf-16be";
    }
    return "utf-8";
  }

  function decodeText(buffer, encoding) {
    let decoder;
    try {
      decoder = new TextDecoder(encoding);
    } catch (error) {
      decoder = new TextDecoder("utf-8");
    }

    let text = decoder.decode(buffer);
    if (encoding === "utf-8" && looksLikeMojibake(text)) {
      try {
        text = new TextDecoder("gb18030").decode(buffer);
      } catch (error) {
        console.warn(error);
      }
    }
    return text;
  }

  function looksLikeMojibake(text) {
    if (!text) {
      return false;
    }
    const replacementCount = (text.match(/\uFFFD/g) || []).length;
    return replacementCount > Math.max(3, text.length / 180);
  }

  function loadJson(key, fallback) {
    try {
      const raw = localStorage.getItem(key);
      return raw ? { ...fallback, ...JSON.parse(raw) } : { ...fallback };
    } catch (error) {
      return { ...fallback };
    }
  }

  function getFileExtension(name) {
    const index = name.lastIndexOf(".");
    return index >= 0 ? name.slice(index + 1).toLowerCase() : "";
  }

  function getFileFingerprint(file) {
    return `${file.name}__${file.size}__${file.lastModified}`;
  }

  function formatBytes(bytes) {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  }

  function normalizeHref(href) {
    return String(href || "").split("#")[0];
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function escapeHtml(text) {
    return String(text)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function throttle(fn, wait) {
    let timer = null;
    return function throttled(...args) {
      if (timer) {
        return;
      }
      timer = setTimeout(() => {
        timer = null;
        fn.apply(this, args);
      }, wait);
    };
  }
})();
