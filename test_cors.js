const url = "https://github.com/MuguDEV/ArcPDF/releases/latest/download/ArcPDF-universal.apk";
fetch(url, { method: "HEAD" })
  .then(res => console.log("Success:", res.ok))
  .catch(err => console.error("Error:", err));
