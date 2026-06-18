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

const suggestionForm = document.querySelector("[data-suggestion-form]");
const formStatus = document.querySelector("[data-form-status]");

const encodeForm = form => new URLSearchParams(new FormData(form)).toString();

if (suggestionForm) {
  suggestionForm.addEventListener("submit", event => {
    event.preventDefault();

    const submitButton = suggestionForm.querySelector("button[type='submit']");
    if (submitButton) {
      submitButton.disabled = true;
      submitButton.textContent = "Sending...";
    }
    if (formStatus) {
      formStatus.textContent = "";
      formStatus.className = "form-status";
    }

    fetch("/", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: encodeForm(suggestionForm)
    })
      .then(response => {
        if (!response.ok) {
          throw new Error(`Form submission failed with status ${response.status}`);
        }
        suggestionForm.reset();
        if (formStatus) {
          formStatus.textContent = "Sent. Thanks for the idea.";
          formStatus.className = "form-status success";
        }
      })
      .catch(error => {
        if (formStatus) {
          formStatus.textContent = `That did not send (${error.message}). Try again, or text Jordan the idea for now.`;
          formStatus.className = "form-status error";
        }
      })
      .finally(() => {
        if (submitButton) {
          submitButton.disabled = false;
          submitButton.textContent = "Submit Suggestion";
        }
      });
  });
}
