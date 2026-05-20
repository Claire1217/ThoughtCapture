chrome.commands.onCommand.addListener((command) => {
  if (command === "capture-thought") {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (tabs[0]) {
        chrome.tabs.sendMessage(tabs[0].id, { action: "open-capture" });
      }
    });
  }
});
