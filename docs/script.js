const buttons = document.querySelectorAll("[data-preview]");
const image = document.querySelector("#preview-image");
const caption = document.querySelector("#preview-caption");
const original = document.querySelector("#preview-original");
buttons.forEach((button) => {
  button.addEventListener("click", () => {
    const theme = button.dataset.preview;
    const label = theme === "dark" ? "深色" : "浅色";
    buttons.forEach((item) =>
      item.setAttribute("aria-pressed", String(item === button)),
    );
    image.src = `assets/overview-${theme}.png`;
    image.alt = `Clean ${label}主题实际运行界面`;
    caption.textContent = `Clean · ${label}主题`;
    original.href = image.getAttribute("src");
  });
});
