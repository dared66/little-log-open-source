// The OAuth token is supplied in memory, never in a URL or local storage.
window.littleLogPick = function (token, key, appId, fileId) {
  return new Promise((resolve, reject) => {
    const show = () => {
      gapi.load('picker', {
        callback: () => {
          const view = new google.picker.DocsView(google.picker.ViewId.DOCS)
            .setIncludeFolders(false)
            .setMimeTypes('text/csv,application/csv');
          const picker = new google.picker.PickerBuilder()
            .setDeveloperKey(key)
            .setAppId(appId)
            .setOAuthToken(token)
            .setOrigin(window.location.origin)
            .setTitle('Choose a baby to add to Little Log')
            .addView(view)
            .setCallback(data => {
              if (data.action === google.picker.Action.PICKED) {
                resolve(data.docs[0].id);
                picker.dispose();
              } else if (data.action === google.picker.Action.CANCEL) {
                resolve(null);
                picker.dispose();
              } else if (data.action === 'error') {
                reject(new Error('Google Picker failed'));
              }
            }).build();
          picker.setVisible(true);
        },
        onerror: () => reject(new Error('Google Picker failed to load')),
        timeout: 15000,
        ontimeout: () => reject(new Error('Google Picker load timed out'))
      });
    };
    if (window.gapi) { show(); return; }
    const script = document.createElement('script');
    script.src = 'https://apis.google.com/js/api.js';
    script.onload = show;
    script.onerror = () => reject(new Error('Google API failed to load'));
    document.head.appendChild(script);
  });
};
