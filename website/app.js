const board = document.querySelector("[data-request-board]");

const statusLabels = {
  done: "Done",
  planned: "Planned",
  requested: "Requested"
};

const renderRequests = requests => {
  if (!board) return;

  board.innerHTML = "";
  requests.forEach(item => {
    const article = document.createElement("article");
    article.className = `request-card ${item.status}`;

    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.checked = item.status === "done";
    checkbox.disabled = true;
    checkbox.setAttribute("aria-label", `${item.title} status`);

    const content = document.createElement("div");
    const title = document.createElement("h3");
    title.textContent = item.title;

    const meta = document.createElement("p");
    meta.className = "request-meta";
    meta.textContent = `${statusLabels[item.status] || "Requested"} by ${item.requestedBy}`;

    const note = document.createElement("p");
    note.textContent = item.note;

    content.append(title, meta, note);
    article.append(checkbox, content);
    board.append(article);
  });
};

fetch("/requests.json")
  .then(response => response.json())
  .then(renderRequests)
  .catch(() => {
    if (board) {
      board.innerHTML = "<p>Could not load the update board right now.</p>";
    }
  });
