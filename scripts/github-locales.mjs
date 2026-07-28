export const githubLocales = Object.freeze([
  { locale: "en", name: "English", canonicalReadme: "README.md" },
  {
    locale: "zh-Hans",
    name: "简体中文",
    canonicalReadme: "README.zh-CN.md",
  },
  {
    locale: "zh-Hant",
    name: "繁體中文",
    canonicalReadme: "docs/readme/README.zh-Hant.md",
  },
  {
    locale: "hi",
    name: "हिन्दी",
    canonicalReadme: "docs/readme/README.hi.md",
  },
  {
    locale: "es-419",
    name: "Español (Latinoamérica)",
    canonicalReadme: "docs/readme/README.es-419.md",
  },
  {
    locale: "es-ES",
    name: "Español (España)",
    canonicalReadme: "docs/readme/README.es-ES.md",
  },
  {
    locale: "ar",
    name: "العربية",
    canonicalReadme: "docs/readme/README.ar.md",
    direction: "rtl",
  },
  {
    locale: "fr",
    name: "Français",
    canonicalReadme: "docs/readme/README.fr.md",
  },
  {
    locale: "bn",
    name: "বাংলা",
    canonicalReadme: "docs/readme/README.bn.md",
  },
  {
    locale: "pt-BR",
    name: "Português (Brasil)",
    canonicalReadme: "docs/readme/README.pt-BR.md",
  },
  {
    locale: "pt-PT",
    name: "Português (Portugal)",
    canonicalReadme: "docs/readme/README.pt-PT.md",
  },
  {
    locale: "id",
    name: "Bahasa Indonesia",
    canonicalReadme: "docs/readme/README.id.md",
  },
  {
    locale: "ur",
    name: "اردو",
    canonicalReadme: "docs/readme/README.ur.md",
    direction: "rtl",
  },
  {
    locale: "ru",
    name: "Русский",
    canonicalReadme: "docs/readme/README.ru.md",
  },
  {
    locale: "de",
    name: "Deutsch",
    canonicalReadme: "docs/readme/README.de.md",
  },
  {
    locale: "ja",
    name: "日本語",
    canonicalReadme: "docs/readme/README.ja.md",
  },
  {
    locale: "sw",
    name: "Kiswahili",
    canonicalReadme: "docs/readme/README.sw.md",
  },
  {
    locale: "pa-Arab",
    name: "پنجابی",
    canonicalReadme: "docs/readme/README.pa-Arab.md",
    direction: "rtl",
  },
  {
    locale: "te",
    name: "తెలుగు",
    canonicalReadme: "docs/readme/README.te.md",
  },
  {
    locale: "pcm",
    name: "Naijá",
    canonicalReadme: "docs/readme/README.pcm.md",
  },
]);

export const githubLocaleCodes = Object.freeze(
  githubLocales.map(({ locale }) => locale),
);

export function generatedReadmePath(locale) {
  return `docs/readme/README.${locale}.md`;
}
