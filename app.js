const input = document.querySelector('#image-input');
const uploadPreview = document.querySelector('#upload-preview');
const uploadZone = document.querySelector('.upload-zone');
const startButton = document.querySelector('#start-button');
const setupView = document.querySelector('.setup-view');
const gameView = document.querySelector('#game-view');
const board = document.querySelector('#board');
const selectedCount = document.querySelector('#selected-count');
const progressValue = document.querySelector('#progress-value');
const timerLabel = document.querySelector('#timer');
const gameDifficulty = document.querySelector('#game-difficulty');
const gameTitle = document.querySelector('#game-title');
let imageUrl = '', imageRatio = 16 / 9, pieces = 9, difficultyLabel = '简单', arrangement = [], selected = null, timerId, elapsed = 0;

function chooseGrid(count, ratio) {
  let best = { rows: 1, cols: count, score: Infinity };
  for (let rows = 1; rows <= Math.sqrt(count); rows++) if (count % rows === 0) {
    const cols = count / rows;
    const score = Math.abs(Math.log((cols / rows) / ratio));
    if (score < best.score) best = { rows, cols, score };
  }
  return best;
}

function formatTime(seconds) { return `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`; }

function renderBoard() {
  const grid = chooseGrid(pieces, imageRatio);
  board.style.gridTemplateColumns = `repeat(${grid.cols}, 1fr)`;
  board.style.gridTemplateRows = `repeat(${grid.rows}, 1fr)`;
  board.innerHTML = '';
  arrangement.forEach((pieceIndex, position) => {
    const tile = document.createElement('button');
    tile.className = 'piece'; tile.type = 'button'; tile.setAttribute('aria-label', `第 ${pieceIndex + 1} 块拼图`);
    const row = Math.floor(pieceIndex / grid.cols), col = pieceIndex % grid.cols;
    tile.style.backgroundImage = `url("${imageUrl}")`;
    tile.style.backgroundSize = `${grid.cols * 100}% ${grid.rows * 100}%`;
    tile.style.backgroundPosition = `${grid.cols === 1 ? 0 : (col / (grid.cols - 1)) * 100}% ${grid.rows === 1 ? 0 : (row / (grid.rows - 1)) * 100}%`;
    tile.addEventListener('click', () => selectTile(position, tile));
    board.appendChild(tile);
  });
  const correct = arrangement.filter((value, index) => value === index).length;
  progressValue.textContent = `${Math.round((correct / pieces) * 100)}%`;
  if (correct === pieces) finishGame();
}

function selectTile(position, tile) {
  if (selected === null) { selected = { position, tile }; tile.classList.add('selected'); return; }
  if (selected.position === position) { tile.classList.remove('selected'); selected = null; return; }
  [arrangement[selected.position], arrangement[position]] = [arrangement[position], arrangement[selected.position]];
  selected = null; renderBoard();
}

function shuffle() { arrangement = Array.from({ length: pieces }, (_, i) => i); do { arrangement.sort(() => Math.random() - 0.5); } while (arrangement.every((value, index) => value === index) && pieces > 1); selected = null; elapsed = 0; timerLabel.textContent = formatTime(elapsed); renderBoard(); }
function finishGame() { clearInterval(timerId); gameTitle.textContent = '拼图完成！'; document.querySelector('#board-hint').textContent = `用时 ${formatTime(elapsed)} · 做得漂亮`; }

input.addEventListener('change', event => { const file = event.target.files[0]; if (!file) return; imageUrl = URL.createObjectURL(file); const img = new Image(); img.onload = () => { imageRatio = img.width / img.height; uploadPreview.innerHTML = `<img class="upload-thumb" src="${imageUrl}" alt="已选择的图片" /><strong>${file.name}</strong>`; uploadZone.classList.add('has-image'); startButton.disabled = false; }; img.src = imageUrl; });
document.querySelectorAll('.difficulty').forEach(button => button.addEventListener('click', () => { document.querySelectorAll('.difficulty').forEach(item => { item.classList.remove('active'); item.setAttribute('aria-checked', 'false'); }); button.classList.add('active'); button.setAttribute('aria-checked', 'true'); pieces = Number(button.dataset.pieces); difficultyLabel = button.dataset.label; selectedCount.textContent = `${pieces} 片`; }));
startButton.addEventListener('click', () => { setupView.classList.add('hidden'); gameView.classList.remove('hidden'); gameDifficulty.textContent = difficultyLabel; gameTitle.textContent = `${difficultyLabel}模式`; shuffle(); clearInterval(timerId); timerId = setInterval(() => { elapsed++; timerLabel.textContent = formatTime(elapsed); }, 1000); window.scrollTo({ top: 0, behavior: 'smooth' }); });
document.querySelector('#reset-button').addEventListener('click', shuffle);
document.querySelector('#back-button').addEventListener('click', () => { clearInterval(timerId); gameView.classList.add('hidden'); setupView.classList.remove('hidden'); });
