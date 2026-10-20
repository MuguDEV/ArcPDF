from playwright.sync_api import sync_playwright

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
URL = "http://127.0.0.1:8765/index.html"
QA = r"C:\Users\themu\Desktop\Arcpdf\ArcPDF\docs\.qa"

with sync_playwright() as p:
    browser = p.chromium.launch(
        executable_path=CHROME,
        headless=True,
        args=["--no-sandbox", "--disable-gpu", "--hide-scrollbars"],
    )
    page = browser.new_page(viewport={"width": 1440, "height": 1000}, color_scheme="light")
    messages = []
    page.on("console", lambda msg: messages.append(f"{msg.type}: {msg.text}"))
    page.on("pageerror", lambda error: messages.append(f"pageerror: {error}"))

    page.goto(URL, wait_until="networkidle")
    page.wait_for_timeout(1500)

    print("title:", page.title())
    print("theme:", page.evaluate("document.documentElement.dataset.theme"))
    print("fonts:", page.evaluate("document.fonts.check('16px \"Bricolage Grotesque\"')"))
    print("release cards:", page.locator(".release").count())
    print("latest body:", repr(page.locator(".release--latest .release-body").inner_text()[:300]))
    print("version:", page.locator("#version-text").inner_text())
    print("download:", page.locator("#hero-download").get_attribute("href"))
    print("horizontal overflow:", page.evaluate("document.documentElement.scrollWidth - window.innerWidth"))
    print("page height:", page.evaluate("document.documentElement.scrollHeight"))

    data = page.evaluate("""async () => {
        const response = await fetch('https://api.github.com/repos/MuguDEV/ArcPDF/releases?per_page=2', {
            headers: { Accept: 'application/vnd.github+json' }
        });
        return { status: response.status, data: await response.json() };
    }""")
    print("api status:", data["status"])
    if isinstance(data["data"], list):
        for release in data["data"][:2]:
            body = release.get("body") or ""
            print(release.get("tag_name"), "body length:", len(body), "sample:", repr(body[:500]))
    else:
        print("api payload:", data["data"])

    page.screenshot(path=f"{QA}\\light-1440.png", full_page=True)
    print("console:", messages[:10])
    browser.close()
