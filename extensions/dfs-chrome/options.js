let input_endPoint = document.getElementById("endpoint");

chrome.storage.sync.get("endpoint", ({endpoint}) => {
  input_endPoint.value = endpoint;
});

input_endPoint.addEventListener('input', () => {
  chrome.storage.sync.set({
    endpoint : input_endPoint.value
  });
});