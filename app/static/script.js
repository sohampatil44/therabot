document.addEventListener('DOMContentLoaded', () => {

    // --- Helper function to add message to chat display ---
    function addMessageToChat(sender, message, container, emotion = null, isPlaceholder = false) {
        const messageDiv = document.createElement('div');
        messageDiv.classList.add('chat-message', sender);
        if (isPlaceholder) {
            messageDiv.classList.add('placeholder'); // Add a class for easy selection
        }

        const nameStrong = document.createElement('strong');
        nameStrong.textContent = (sender === 'user' ? 'You:' : 'Therabot:');

        const messageP = document.createElement('p');
        messageP.textContent = message;

        const innerP = document.createElement('p');
        innerP.appendChild(nameStrong);

        // Only add emotion tag if it's NOT a placeholder and emotion is relevant
        if (sender === 'bot' && !isPlaceholder && emotion && emotion !== 'neutral' && emotion !== 'error') {
            const emotionSpan = document.createElement('span');
            emotionSpan.classList.add('emotion-tag');
            emotionSpan.textContent = ` (${emotion})`;
            innerP.appendChild(emotionSpan);
        }

        messageDiv.appendChild(innerP);
        messageDiv.appendChild(messageP);

        container.appendChild(messageDiv);
        scrollToBottom(container);
        return messageDiv; // Return the created element
    }

    // --- Helper function to scroll chat history ---
    function scrollToBottom(container) {
        if (container) {
            setTimeout(() => {
                container.scrollTop = container.scrollHeight;
            }, 0);
        }
    }

    // --- FAQ Accordion ---
    const faqItems = document.querySelectorAll('.faq-item');
    faqItems.forEach(item => {
        const question = item.querySelector('.faq-question');
        if (question) {
            question.addEventListener('click', () => {
                item.classList.toggle('active');
            });
        }
    });

    // --- Auto-scroll Chat (Initial Load) ---
    const chatHistoryContainer = document.getElementById('chat-history');
    if (chatHistoryContainer) {
        scrollToBottom(chatHistoryContainer);
    }

    // --- Add 'active' class to current nav link ---
    const navLinks = document.querySelectorAll('header nav a');
    const currentPath = window.location.pathname;

    navLinks.forEach(link => {
        if (link.getAttribute('href') === currentPath) {
            if (!link.classList.contains('active')) {
                link.classList.add('active');
            }
        }
    });

    // --- Simple Placeholder Animation on Resource Cards ---
    const resourceCards = document.querySelectorAll('.resource-card');
    resourceCards.forEach((card, index) => {
        card.style.animation = `resourceFadeIn 0.6s ease-out ${index * 0.1}s forwards`;
    });

    // --- Theme Toggle ---
    const themeToggle = document.getElementById('theme-toggle');
    const body = document.body;
    const currentTheme = localStorage.getItem('theme');

    if (currentTheme === 'dark') {
        body.classList.add('dark-mode');
        if (themeToggle) {
            themeToggle.innerHTML = '☀️';
            themeToggle.title = "Switch to light mode";
        }
    } else {
        if (themeToggle) {
            themeToggle.innerHTML = '🌙';
            themeToggle.title = "Switch to dark mode";
        }
    }

    if (themeToggle) {
        themeToggle.addEventListener('click', () => {
            body.classList.toggle('dark-mode');
            if (body.classList.contains('dark-mode')) {
                localStorage.setItem('theme', 'dark');
                themeToggle.innerHTML = '☀️';
                themeToggle.title = "Switch to light mode";
            } else {
                localStorage.setItem('theme', 'light');
                themeToggle.innerHTML = '🌙';
                themeToggle.title = "Switch to dark mode";
            }
        });
    }

    // --- AJAX Chat Form Submission ---
    const chatForm = document.getElementById('chat-form');
    const chatInput = document.getElementById('chat-input');
    const rainAudio = document.getElementById('rain-audio'); // Get audio element
    const rainToggleButton = document.getElementById('rain-toggle-button'); // Get toggle button
    const audioControls = document.getElementById('audio-controls'); // Get audio controls container
    const volumeSlider = document.getElementById('volume-slider'); // Get volume slider

    // --- Rain Audio Functions ---
    function playRainSound() {
        if (rainAudio && audioControls) {
            // Set initial volume from slider if available
            if (volumeSlider) {
                rainAudio.volume = volumeSlider.value;
            }
            rainAudio.play().catch(e => console.error("Error playing audio:", e));
            audioControls.style.display = 'flex'; // Show the audio controls container
        }
    }

    function stopRainSound() {
        if (rainAudio) {
            rainAudio.pause();
            rainAudio.currentTime = 0; // Reset audio to start
            if (audioControls) {
                audioControls.style.display = 'none'; // Hide the audio controls container
            }
        }
    }

    function toggleRainSound() {
        if (rainAudio && !rainAudio.paused) {
            stopRainSound();
        }
    }
    // --------------------------

    // Add listener for the rain toggle button
    if (rainToggleButton) {
        rainToggleButton.addEventListener('click', toggleRainSound);
    }

    // Add listener for the volume slider
    if (volumeSlider && rainAudio) {
        // Set initial audio volume based on slider's default value
        rainAudio.volume = volumeSlider.value;
        
        volumeSlider.addEventListener('input', () => {
            rainAudio.volume = volumeSlider.value;
        });
    }

    if (chatForm && chatInput && chatHistoryContainer) {
        chatForm.addEventListener('submit', async (event) => {
            event.preventDefault();

            const userMessage = chatInput.value.trim();
            if (!userMessage) {
                return;
            }

            // --- Check for "stop music" command ---
            if (userMessage.toLowerCase().includes('stop music')) {
                stopRainSound();
                chatInput.value = ''; // Clear input
                chatInput.focus();
                return; // Stop processing this message further
            }
            // ------------------------------------

            // Add user message
            addMessageToChat('user', userMessage, chatHistoryContainer);
            chatInput.value = '';
            chatInput.focus();

            // Add placeholder for bot response
            let placeholderMessageElement = addMessageToChat('bot', '...', chatHistoryContainer, null, true);

            try {
                const response = await fetch(chatForm.action, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json'
                    },
                    body: JSON.stringify({ message: userMessage })
                });

                // Find the placeholder to update/remove it
                const placeholder = chatHistoryContainer.querySelector('.chat-message.bot.placeholder');

                if (!response.ok) {
                    let errorMsg = `Error: ${response.status} ${response.statusText}`;
                    try {
                        const errorData = await response.json();
                        errorMsg = errorData.error || errorMsg;
                    } catch (e) { }
                    console.error('Fetch Error:', errorMsg);
                    if (placeholder) {
                        // Update placeholder with error
                        placeholder.querySelector('p:last-child').textContent = `Sorry, couldn't get a response. ${errorMsg}`;
                        placeholder.classList.remove('placeholder'); // Remove placeholder status
                    } else {
                        // Fallback if placeholder somehow missing
                        addMessageToChat('bot', `Sorry, couldn't get a response. ${errorMsg}`, chatHistoryContainer, 'error');
                    }
                    return;
                }

                const data = await response.json();

                if (placeholder) {
                    placeholder.classList.remove('placeholder'); // Remove placeholder status
                    if (data.error) {
                        console.error('App Error:', data.error);
                        placeholder.querySelector('p:last-child').textContent = data.error;
                    } else if (data.warning) {
                        console.warn('App Warning:', data.warning);
                        placeholder.querySelector('p:last-child').textContent = data.warning;
                    } else if (data.bot_reply) {
                        // Update placeholder content with the actual reply
                        // Replace newlines from backend with <br> for HTML display
                        placeholder.querySelector('p:last-child').innerHTML = data.bot_reply.replace(/\n/g, '<br>');

                        // Add emotion tag if present
                        if (data.emotion && data.emotion !== 'neutral') {
                            const emotionSpan = document.createElement('span');
                            emotionSpan.classList.add('emotion-tag');
                            emotionSpan.textContent = ` (${data.emotion})`;
                            // Ensure the strong tag exists before appending
                            const strongTag = placeholder.querySelector('p:first-child strong');
                            if (strongTag) {
                                strongTag.parentNode.appendChild(emotionSpan);
                            }
                        }

                        // --- Rain Audio Control ---
                        if (data.play_rain) {
                            playRainSound();
                        }
                        // --------------------------

                        if (data.action === 'end_chat') {
                            chatInput.disabled = true;
                            chatInput.placeholder = "Chat ended. Refresh to start again.";
                            stopRainSound(); // Stop rain sound if chat ends
                        }
                    }
                } else {
                    // Fallback if placeholder is missing
                    if (data.error) addMessageToChat('bot', data.error, chatHistoryContainer, 'error');
                    else if (data.warning) addMessageToChat('bot', data.warning, chatHistoryContainer, 'warning');
                    else if (data.bot_reply) {
                        addMessageToChat('bot', data.bot_reply.replace(/\n/g, '<br>'), chatHistoryContainer, data.emotion);
                        // --- Rain Audio Control (Fallback) ---
                        if (data.play_rain) {
                            playRainSound();
                        }
                        // --------------------------
                    }
                }

                // Scroll after adding/updating message
                scrollToBottom(chatHistoryContainer);

            } catch (error) {
                console.error('Network/Fetch Error:', error);
                // Update or add error message in placeholder or new message
                const placeholder = chatHistoryContainer.querySelector('.chat-message.bot.placeholder');
                if (placeholder) {
                    placeholder.querySelector('p:last-child').textContent = 'Sorry, there was a network problem. Please check your connection and try again.';
                    placeholder.classList.remove('placeholder');
                } else {
                    addMessageToChat('bot', 'Sorry, there was a network problem. Please check your connection and try again.', chatHistoryContainer, 'error');
                }
                scrollToBottom(chatHistoryContainer); // Scroll after error message
            }
        });
    }

}); // End DOMContentLoaded

// --- Add Keyframe for Resource Card Animation ---
const styleSheet = document.styleSheets[0];
try {
    styleSheet.insertRule(`
        @keyframes resourceFadeIn {
            from { opacity: 0; transform: translateY(15px); }
            to { opacity: 1; transform: translateY(0); }
        }
    `, styleSheet.cssRules.length);
} catch (e) {
    console.warn("Could not insert resourceFadeIn keyframe dynamically: ", e);
}
