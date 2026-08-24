const storageKey = "trialGuideUserId";
const localApiHostnames = new Set(["localhost", "127.0.0.1"]);
const apiBaseUrl = localApiHostnames.has(window.location.hostname)
  ? "http://localhost:5228"
  : "";

const questionList = document.querySelector("#question-list");
const messages = document.querySelector("#messages");
const status = document.querySelector("#status");
const chatForm = document.querySelector("#chat-form");
const messageInput = document.querySelector("#message-input");
const sendButton = document.querySelector("#send-button");
const forgetButton = document.querySelector("#forget-button");
const runtimeLabel = document.querySelector("#runtime-label");

let userId = getOrCreateUserId();
let isSending = false;

chatForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  await sendMessage(messageInput.value);
});

forgetButton.addEventListener("click", async () => {
  const shouldForget = window.confirm(
    "Delete this browser's saved demo conversation and start over?"
  );

  if (!shouldForget) {
    return;
  }

  setBusy(true, "Deleting your saved conversation...");

  try {
    const response = await fetch(apiUrl(`/api/history/${encodeURIComponent(userId)}`), {
      method: "DELETE"
    });

    if (!response.ok) {
      throw new Error(await getErrorMessage(response));
    }

    localStorage.removeItem(storageKey);
    userId = getOrCreateUserId();
    showWelcome();
    setStatus("Your saved demo conversation was deleted.");
  } catch (error) {
    setStatus(error.message, true);
  } finally {
    setBusy(false);
  }
});

await loadPage();

async function loadPage() {
  setStatus("Loading your conversation...");

  const results = await Promise.allSettled([
    loadRuntime(),
    loadQuestions(),
    loadHistory()
  ]);
  const failure = results.find((result) => result.status === "rejected");

  if (failure) {
    setStatus(failure.reason.message, true);
    return;
  }

  setStatus("");
}

async function loadRuntime() {
  const response = await fetch(apiUrl("/api/runtime"));
  if (!response.ok) {
    throw new Error(await getErrorMessage(response));
  }

  const runtime = await response.json();
  runtimeLabel.textContent = runtime.mode === "local-demo"
    ? "Local demo - canned responses"
    : "Microsoft Foundry demo";
}

async function loadQuestions() {
  const response = await fetch(apiUrl("/api/questions"));
  if (!response.ok) {
    throw new Error(await getErrorMessage(response));
  }

  const questions = await response.json();
  questionList.replaceChildren();

  for (const question of questions) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "question-button";
    button.textContent = question.text;
    button.addEventListener("click", () => sendMessage(question.text));
    questionList.append(button);
  }
}

async function loadHistory() {
  const response = await fetch(apiUrl(`/api/history/${encodeURIComponent(userId)}`));
  if (!response.ok) {
    throw new Error(await getErrorMessage(response));
  }

  const history = await response.json();
  messages.replaceChildren();

  if (history.length === 0) {
    showWelcome();
    return;
  }

  for (const message of history) {
    appendMessage(message.role, message.content);
  }
}

async function sendMessage(rawMessage) {
  const message = rawMessage.trim();
  if (!message || isSending) {
    return;
  }

  appendMessage("user", message);
  messageInput.value = "";
  setBusy(true, "TrialGuide is thinking...");

  try {
    const response = await fetch(apiUrl("/api/chat"), {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        userId,
        message
      })
    });

    if (!response.ok) {
      throw new Error(await getErrorMessage(response));
    }

    const result = await response.json();
    appendMessage(result.message.role, result.message.content);
    setStatus("");
  } catch (error) {
    setStatus(error.message, true);
  } finally {
    setBusy(false);
    messageInput.focus();
  }
}

function appendMessage(role, content) {
  const message = document.createElement("article");
  const label = document.createElement("span");
  const body = document.createElement("span");

  message.className = `message message-${role}`;
  label.className = "message-label";
  label.textContent = role === "user" ? "You" : "TrialGuide";
  body.textContent = content;

  message.append(label, body);
  messages.append(message);
  messages.scrollTop = messages.scrollHeight;
}

function showWelcome() {
  messages.replaceChildren();
  appendMessage(
    "assistant",
    "Hello. I can explain common clinical trial terms and what participants may want to ask a study team. What would you like to know?"
  );
}

function setBusy(busy, message = "") {
  isSending = busy;
  sendButton.disabled = busy;
  messageInput.disabled = busy;
  forgetButton.disabled = busy;

  for (const button of questionList.querySelectorAll("button")) {
    button.disabled = busy;
  }

  if (message) {
    setStatus(message);
  }
}

function setStatus(message, isError = false) {
  status.textContent = message;
  status.classList.toggle("status-error", isError);
}

function apiUrl(path) {
  return `${apiBaseUrl}${path}`;
}

function getOrCreateUserId() {
  const existingUserId = localStorage.getItem(storageKey);
  if (existingUserId) {
    return existingUserId;
  }

  const newUserId = `demo-${crypto.randomUUID()}`;
  localStorage.setItem(storageKey, newUserId);
  return newUserId;
}

async function getErrorMessage(response) {
  try {
    const problem = await response.json();
    const validationMessage = Object.values(problem.errors ?? {})
      .flat()
      .find(Boolean);
    return validationMessage ?? problem.detail ?? problem.title ?? "The request failed.";
  } catch {
    return `The request failed with status ${response.status}.`;
  }
}
