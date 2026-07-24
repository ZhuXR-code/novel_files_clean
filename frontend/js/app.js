/**
 * 文件扫描管理系统 - 前端逻辑
 */

const API_BASE = '/api';

// ===================== 状态管理 =====================
let state = {
    configs: [],
    results: [],
    groups: [],
    columnConfigs: [],
    selectedIds: new Set(),
    expandedIds: new Set(),
    currentConfigId: null,
    sortBy: 'id',
    sortOrder: 'desc',
    sortClicks: {},
    searchText: '',
    scanningIds: new Set(),
    groupByFileName: false,
    minGroupCount: 0,
    maxGroupCount: null,       // 合集文件数上限（null 表示不限制）
    excludeGroupNames: '',
    expandedGroups: new Set(),    // 已展开的合集（合集模式默认全部展开，文件行按需懒加载）
    // 分页
    page: 1,
    pageSize: 100,
    total: 0,
    totalPages: 1,
    totalGroups: 0,
    // 小说名筛选
    filterNovelNames: [],       // 从后端获取的小说名列表 [{novel_name, count}]
    selectedNovelNames: new Set(), // 已选中用于筛选的小说名
    filterSearchText: '',       // 筛选面板内的搜索文本
    showFilterDropdown: false,  // 筛选面板是否显示
    activeNovelNames: new Set(),// 当前生效的筛选（已应用的）
    filterPage: 1,              // 筛选面板当前页码
    checkedFilter: 'all',       // 勾选状态筛选: 'all' | 'checked' | 'unchecked'
    filterTotalPages: 1,       // 筛选面板总页数
    filterTotalItems: 0,       // 筛选面板总条数
    filterPageSize: 100,       // 筛选面板每页条数
    filterLoading: false,      // 筛选面板加载状态
    filterListRendered: false, // 筛选列表是否已渲染（用于事件委托）
    parseConcurrency: 12,       // 解析默认并发数
    // 行内编辑
    editingIds: new Set(),      // 正在编辑的行ID集合
    editData: {},               // { rowId: { columnKey: value } }
};

// ===================== 工具函数 =====================
function toast(message, type = 'info') {
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.textContent = message;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 3000);
}

function closeModal(id) {
    document.getElementById(id).style.display = 'none';
}

function openModal(id) {
    document.getElementById(id).style.display = 'flex';
}

function escapeHtml(str) {
    if (str === null || str === undefined || str === '') return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

// ===================== API 调用 =====================
async function apiGet(url) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 30000);
    try {
        const sep = url.includes('?') ? '&' : '?';
        const resp = await fetch(`${API_BASE}${url}${sep}_t=${Date.now()}`, {
            signal: controller.signal,
            cache: 'no-cache',
        });
        if (!resp.ok) {
            const text = await resp.text();
            let msg;
            try { const j = JSON.parse(text); msg = j.detail || text; } catch (e) { msg = text; }
            throw new Error(msg);
        }
        return resp.json();
    } catch (e) {
        if (e.name === 'AbortError') throw new Error('请求超时，请检查服务是否繁忙');
        if (e.message === 'Failed to fetch') throw new Error('无法连接到服务，请检查服务是否运行');
        throw e;
    } finally {
        clearTimeout(timeoutId);
    }
}

async function apiPost(url, body, timeout = 30000) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);
    try {
        const opts = {
            method: 'POST',
            signal: controller.signal,
        };
        if (body !== undefined && body !== null) {
            opts.headers = { 'Content-Type': 'application/json' };
            opts.body = JSON.stringify(body);
        }
        const resp = await fetch(`${API_BASE}${url}`, opts);
        if (!resp.ok) {
            const text = await resp.text();
            let msg;
            try { const j = JSON.parse(text); msg = j.detail || text; } catch (e) { msg = text; }
            throw new Error(msg);
        }
        return resp.json();
    } catch (e) {
        if (e.name === 'AbortError') throw new Error('请求超时，请检查服务是否繁忙');
        if (e.message === 'Failed to fetch') throw new Error('无法连接到服务，请检查服务是否运行');
        throw e;
    } finally {
        clearTimeout(timeoutId);
    }
}

async function apiPut(url, data) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 30000);
    try {
        const resp = await fetch(`${API_BASE}${url}`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data),
            signal: controller.signal,
        });
        if (!resp.ok) {
            const text = await resp.text();
            try {
                const j = JSON.parse(text);
                throw new Error(j.detail || JSON.stringify(j));
            } catch (e) {
                if (e.message && !e.message.startsWith('{')) throw e;
                throw new Error(`请求失败(${resp.status}): ${text.slice(0, 200)}`);
            }
        }
        return resp.json();
    } catch (e) {
        if (e.name === 'AbortError') {
            throw new Error('请求超时，请检查服务是否繁忙');
        }
        if (e.message === 'Failed to fetch') {
            throw new Error('无法连接到服务，请检查服务是否运行');
        }
        throw e;
    } finally {
        clearTimeout(timeoutId);
    }
}

async function apiDelete(url) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 30000);
    try {
        const resp = await fetch(`${API_BASE}${url}`, { method: 'DELETE', signal: controller.signal });
        if (!resp.ok) {
            const err = await resp.json().catch(() => ({}));
            throw new Error(err.detail || `请求失败: ${resp.status}`);
        }
        return resp.json();
    } catch (e) {
        if (e.name === 'AbortError') throw new Error('请求超时，请检查服务是否繁忙');
        if (e.message === 'Failed to fetch') throw new Error('无法连接到服务，请检查服务是否运行');
        throw e;
    } finally {
        clearTimeout(timeoutId);
    }
}

// ===================== 数据加载 =====================
async function loadConfigs() {
    try {
        state.configs = await apiGet('/configs');
        renderConfigs();
    } catch (e) {
        toast('加载配置失败: ' + e.message, 'error');
    }
}

async function loadColumnConfigs() {
    try {
        state.columnConfigs = await apiGet('/column-configs');
        renderColumnConfigs();
    } catch (e) {
        toast('加载列配置失败: ' + e.message, 'error');
    }
}

async function loadResults() {
    if (!state.currentConfigId) return;

    try {
        // 合集模式加载较慢时显示加载提示
        if (state.groupByFileName) {
            document.getElementById('loadingOverlay').style.display = '';
        }
        const params = new URLSearchParams({
            config_id: state.currentConfigId,
            page: state.page,
            page_size: state.pageSize,
        });
        if (state.groupByFileName) {
            // 使用专用合集 API
            if (state.minGroupCount > 0) {
                params.set('min_count', state.minGroupCount);
            }
            if (state.maxGroupCount != null) {
                params.set('max_count', state.maxGroupCount);
            }
            if (state.excludeGroupNames) {
                params.set('exclude_names', state.excludeGroupNames);
            }
        } else {
            params.set('sort_by', state.sortBy);
            params.set('sort_order', state.sortOrder);
        }
        if (state.searchText) {
            params.set('search', state.searchText);
        }
        if (state.checkedFilter !== 'all') {
            params.set('checked_filter', state.checkedFilter);
        }
        if (state.activeNovelNames.size > 0) {
            params.set('novel_names', Array.from(state.activeNovelNames).join(','));
        }
        const endpoint = state.groupByFileName ? '/groups' : '/results';
        const resp = await apiGet(endpoint + '?' + params.toString());
        if (state.groupByFileName) {
            state.groups = resp.groups || [];
            state.total = resp.total || 0;
            state.totalGroups = resp.total_groups || 0;
            state.totalPages = Math.max(1, Math.ceil((resp.total_groups || 0) / state.pageSize));
            state.results = [];
            // 构建有效ID集用于清理
            const validIds = new Set();
            (resp.groups || []).forEach(g => (g.items || []).forEach(item => validIds.add(item.id)));
            for (const id of state.selectedIds) {
                if (!validIds.has(id)) state.selectedIds.delete(id);
            }
            state.expandedIds.clear();
            state.editingIds.clear();
            state.editData = {};
            // 合集模式默认折叠：避免大库首屏一次性插入所有分组的全部文件行导致浏览器卡死；
            // 用户点击分组头展开时再懒加载该分组的文件行。
            state.expandedGroups = new Set();
            // 从后端同步 checked 状态到客户端 selectedIds
            (resp.groups || []).forEach(g => (g.items || []).forEach(item => {
                if (item.checked) state.selectedIds.add(item.id);
            }));
        } else {
            state.results = resp.items || [];
            state.total = resp.total || 0;
            state.totalPages = resp.total_pages || 1;
            state.groups = [];
            state.totalGroups = 0;
            // 从后端同步 checked 状态（不再直接清空，保留跨扫描配置的勾选）
            state.selectedIds.clear();
            (resp.items || []).forEach(item => {
                if (item.checked) state.selectedIds.add(item.id);
            });
            state.expandedIds.clear();
            state.editingIds.clear();
            state.editData = {};
        }
        renderResults();
        updateStats();
    } catch (e) {
        toast('加载数据失败: ' + e.message, 'error');
    } finally {
        document.getElementById('loadingOverlay').style.display = 'none';
    }
}

let _lastStatsTime = 0;
async function updateStats(force = false) {
    // 节流：翻页/搜索/筛选会频繁触发 loadResults→updateStats，3 秒内不重复请求 /stats（三个 COUNT 查询）
    const now = Date.now();
    if (!force && now - _lastStatsTime < 3000) return;
    _lastStatsTime = now;
    try {
        const stats = await apiGet('/stats');
        document.getElementById('statTotalFiles').textContent = stats.total_files;
        document.getElementById('statParsed').textContent = stats.parsed_count;
    } catch (_) {}
}

// ===================== 扫描配置渲染 =====================
function renderConfigs() {
    const el = document.getElementById('configList');
    if (state.configs.length === 0) {
        el.innerHTML = '<div class="config-item" style="text-align:center;color:var(--text-secondary)">暂无配置，请新增</div>';
        return;
    }

    el.innerHTML = state.configs.map(cfg => {
        const isScanning = state.scanningIds.has(cfg.id);
        const pr = cfg._progress || {};
        const count = pr.count || 0;
        const elapsed = pr.elapsed || 0;
        const elapsedStr = elapsed >= 60 ? `${Math.floor(elapsed/60)}分${elapsed%60}秒` : `${elapsed}秒`;
        return `
        <div class="config-item ${state.currentConfigId === cfg.id ? 'active' : ''}"
             onclick="selectConfig(${cfg.id})">
            <div class="cfg-name">${escapeHtml(cfg.name || cfg.folder_path)}</div>
            <div class="cfg-meta">
                ${cfg.name ? `<span title="${escapeHtml(cfg.folder_path)}">路径: ${escapeHtml(cfg.folder_path)}</span>` : ''}
                <span>类型: ${cfg.file_types}</span>
                <span>${cfg.excluded_folders ? '已排除' : '无排除'}</span>
            </div>
            ${isScanning ? `
            <div class="scan-progress-wrap">
                <div class="scan-progress-text">已处理 ${count} 个文件，耗时 ${elapsedStr}</div>
                <div class="scan-progress-bar-wrap">
                    <div class="scan-progress-bar" style="width:${Math.min(count, 100)}%"></div>
                </div>
            </div>` : ''}
            <div class="cfg-actions">
                <button class="btn-sm" onclick="event.stopPropagation();runScan(${cfg.id})">${isScanning ? '⏳' : '▶'} 扫描</button>
                <button class="btn-sm" onclick="event.stopPropagation();editConfig(${cfg.id})">编辑</button>
                <button class="btn-sm danger" onclick="event.stopPropagation();deleteConfig(${cfg.id})">删除</button>
            </div>
        </div>`;
    }).join('');
}

function selectConfig(id) {
    state.currentConfigId = id;
    state.sortBy = 'id';
    state.sortOrder = 'desc';
    state.sortClicks = {};
    state.page = 1;
    state.searchText = '';
    state.filterNovelNames = [];
    state.selectedNovelNames.clear();
    state.activeNovelNames.clear();
    state.filterSearchText = '';
    state.showFilterDropdown = false;
    state.filterPage = 1;
    state.filterTotalPages = 1;
    state.filterTotalItems = 0;
    state.filterLoading = false;
    state.filterListRendered = false;
    const searchInput = document.getElementById('searchInput');
    if (searchInput) searchInput.value = '';
    const filterDropdown = document.getElementById('filterDropdown');
    if (filterDropdown) filterDropdown.style.display = 'none';
    updateFilterBadge();
    renderConfigs();
    loadResults();
}

// ===================== 扫描配置 CRUD =====================
function showAddConfigModal() {
    document.getElementById('configModalTitle').textContent = '新增扫描配置';
    document.getElementById('cfgName').value = '';
    document.getElementById('cfgFolderPath').value = '';
    document.getElementById('cfgEditId').value = '';
    document.querySelectorAll('#fileTypesGroup input[type="checkbox"]').forEach(cb => cb.checked = false);
    document.querySelector('#fileTypesGroup input[value="txt"]').checked = true;
    document.getElementById('customFileType').value = '';
    document.getElementById('cfgExcludedFolders').value = '';
    document.getElementById('cfgParseOnScan').checked = true;  // 新增配置默认开启同步解析
    // 默认快速扫描模式
    const quickRadio = document.querySelector('input[name="cfgScanMode"][value="quick"]');
    if (quickRadio) quickRadio.checked = true;
    openModal('configModal');
}

function editConfig(id) {
    const cfg = state.configs.find(c => c.id === id);
    if (!cfg) return;
    document.getElementById('configModalTitle').textContent = '编辑扫描配置';
    document.getElementById('cfgName').value = cfg.name || '';
    document.getElementById('cfgFolderPath').value = cfg.folder_path;
    document.getElementById('cfgEditId').value = cfg.id;
    const types = cfg.file_types.split(',').map(t => t.trim());
    document.querySelectorAll('#fileTypesGroup input[type="checkbox"]').forEach(cb => {
        cb.checked = types.includes(cb.value);
    });
    document.getElementById('customFileType').value = '';
    document.getElementById('cfgExcludedFolders').value = cfg.excluded_folders || '';
    document.getElementById('cfgParseOnScan').checked = cfg.parse_on_scan !== false;  // 未明确关闭即视为开启
    // 设置扫描模式
    const scanMode = cfg.scan_mode || 'quick';
    const modeRadio = document.querySelector(`input[name="cfgScanMode"][value="${scanMode}"]`);
    if (modeRadio) modeRadio.checked = true;
    else {
        const defRadio = document.querySelector('input[name="cfgScanMode"][value="quick"]');
        if (defRadio) defRadio.checked = true;
    }
    openModal('configModal');
}

// 扫描模式切换时的描述更新（当前仅占位，后续可扩展动态提示）
function updateScanModeDesc() {}

async function saveConfig() {
    const folderPath = document.getElementById('cfgFolderPath').value.trim();
    if (!folderPath) { toast('请输入文件夹路径', 'warning'); return; }

    const types = [];
    document.querySelectorAll('#fileTypesGroup input[type="checkbox"]:checked').forEach(cb => types.push(cb.value));
    const customType = document.getElementById('customFileType').value.trim();
    if (customType) types.push(customType);
    if (types.length === 0) { toast('请选择至少一个文件类型', 'warning'); return; }

    const data = {
        name: document.getElementById('cfgName').value.trim(),
        folder_path: folderPath,
        file_types: types.join(','),
        excluded_folders: document.getElementById('cfgExcludedFolders').value.trim(),
        scan_mode: (() => { const r = document.querySelector('input[name="cfgScanMode"]:checked'); return r ? r.value : 'quick'; })(),
        parse_on_scan: document.getElementById('cfgParseOnScan').checked,
    };
    const editId = document.getElementById('cfgEditId').value;
    try {
        if (editId) {
            await apiPut(`/configs/${editId}`, data);
            toast('配置已更新', 'success');
        } else {
            await apiPost('/configs', data);
            toast('配置已创建', 'success');
        }
        closeModal('configModal');
        await loadConfigs();
    } catch (e) {
        toast('保存失败: ' + e.message, 'error');
    }
}

async function deleteConfig(id) {
    if (!confirm('确定删除此扫描配置？（关联的扫描结果也将被删除）')) return;
    try {
        await apiDelete(`/configs/${id}`);
        if (state.currentConfigId === id) {
            state.currentConfigId = null;
            state.results = [];
            renderResults();
        }
        toast('配置已删除', 'success');
        await loadConfigs();
    } catch (e) {
        toast('删除失败: ' + e.message, 'error');
    }
}

// ===================== 执行扫描（带进度条） =====================
async function runScan(configId) {
    if (state.scanningIds.has(configId)) {
        toast('该配置正在扫描中...', 'warning');
        return;
    }

    const cfg = state.configs.find(c => c.id === configId);
    if (cfg) cfg._progress = 0;
    state.scanningIds.add(configId);
    renderConfigs();

    // 开始轮询进度
    let refreshCounter = 0;
    const pollTimer = setInterval(async () => {
        try {
            const p = await apiGet(`/scan-progress/${configId}`);
            const cfg2 = state.configs.find(c => c.id === configId);
            if (cfg2) cfg2._progress = p;
            renderConfigs();
            // 每2秒（4次轮询）刷新一次列表，显示边扫描边入库的结果
            refreshCounter++;
            if (refreshCounter >= 4 && state.currentConfigId === configId) {
                refreshCounter = 0;
                await loadResults();
            }
            if (p.done) {
                clearInterval(pollTimer);
            }
        } catch (_) {
            clearInterval(pollTimer);
        }
    }, 500);

    try {
        toast('开始扫描...', 'info');
        const result = await apiPost(`/scan/${configId}`, null, 600000);  // 扫描同步阻塞，10分钟超时
        toast(result.message, 'success');
        state.currentConfigId = configId;
        await loadResults();
        state.scanningIds.delete(configId);
        clearInterval(pollTimer);
        const cfg3 = state.configs.find(c => c.id === configId);
        if (cfg3) cfg3._progress = 100;
        renderConfigs();
        // 扫描时同步工程类解析：等待解析完成后再重建合集，使合集/勾选重复立即可用
        if (result.parse_task_id) {
            currentParseTaskId = result.parse_task_id;
            sessionStorage.setItem('parseTaskId', result.parse_task_id);
            showParseProgress(true);
            const parseOk = await awaitParseTask(result.parse_task_id);
            showParseProgress(false);
            await loadResults();
            await updateStats(true);
            if (!parseOk) toast('工程类解析未正常完成，合集可能不完整', 'warning');
        }
        // 扫描完成后显式触发“重建合集”并在前端展示进度条（大库下可能耗时）
        await rebuildGroups(configId);
    } catch (e) {
        state.scanningIds.delete(configId);
        clearInterval(pollTimer);
        const cfg4 = state.configs.find(c => c.id === configId);
        if (cfg4) cfg4._progress = -1;
        renderConfigs();
        toast('扫描失败: ' + e.message, 'error');
    }
}

// ===================== 重建合集（带进度条） =====================
async function rebuildGroups(configId) {
    const sleep = (ms) => new Promise(r => setTimeout(r, ms));
    const wrap = document.getElementById('rebuildProgress');
    const bar = document.getElementById('rebuildProgressBar');
    const desc = document.getElementById('rebuildProgressDesc');
    const cnt = document.getElementById('rebuildProgressCount');
    if (!wrap) return;
    try {
        const r = await apiPost(`/groups/rebuild/${configId}`);
        if (r.running) {
            // 已有重建任务进行中，直接轮询进度
        }
        // 轮询进度条直到完成
        wrap.style.display = '';
        bar.style.width = '0%';
        desc.textContent = '正在重建合集...';
        cnt.textContent = '0/0';
        for (let i = 0; i < 600; i++) {
            await sleep(300);
            const p = await apiGet(`/rebuild-progress/${configId}`);
            const pct = Math.max(0, Math.min(100, p.percent || 0));
            bar.style.width = pct + '%';
            cnt.textContent = `${p.done_count}/${p.total}`;
            if (p.phase) desc.textContent = '正在重建合集（' + p.phase + '）';
            if (p.done) {
                bar.style.width = '100%';
                desc.textContent = '合集重建完成';
                break;
            }
        }
        // 刷新列表（合集模式需要最新分组）
        await loadResults();
    } catch (e) {
        toast('重建合集失败: ' + (e.message || e), 'error');
    } finally {
        // 稍延迟隐藏，让用户看到 100%
        setTimeout(() => { if (wrap) wrap.style.display = 'none'; }, 600);
    }
}

// ===================== 帮助手册 =====================
async function loadHelpDocs() {
    try {
        const docs = await apiGet('/help');
        const nav = document.getElementById('helpNav');
        if (!docs || docs.length === 0) {
            nav.innerHTML = '<div class="help-nav-loading">暂无帮助内容</div>';
            return;
        }
        nav.innerHTML = docs.map(d =>
            `<div class="help-nav-item" data-key="${escapeHtml(d.doc_key)}" onclick="selectHelpDoc('${escapeHtml(d.doc_key)}')">${escapeHtml(d.title)}</div>`
        ).join('');
        selectHelpDoc(docs[0].doc_key);
    } catch (e) {
        const nav = document.getElementById('helpNav');
        if (nav) nav.innerHTML = '<div class="help-nav-loading">加载失败: ' + escapeHtml(e.message) + '</div>';
    }
}

async function selectHelpDoc(docKey) {
    try {
        const doc = await apiGet('/help/' + encodeURIComponent(docKey));
        const titleEl = document.getElementById('helpDocTitle');
        const bodyEl = document.getElementById('helpDocBody');
        if (titleEl) titleEl.textContent = doc.title || '';
        if (bodyEl) bodyEl.innerHTML = renderMarkdown(doc.content || '');
        document.querySelectorAll('.help-nav-item').forEach(el => {
            el.classList.toggle('active', el.getAttribute('data-key') === docKey);
        });
    } catch (e) {
        toast('加载帮助内容失败: ' + e.message, 'error');
    }
}

function renderMarkdown(md) {
    const lines = escapeHtml(md || '').split('\n');
    let html = '';
    let para = [];
    function flushPara() {
        if (para.length) {
            html += '<p>' + para.join('<br>') + '</p>';
            para = [];
        }
    }
    let i = 0;
    while (i < lines.length) {
        const line = lines[i];
        if (/^```/.test(line)) {
            flushPara();
            const code = [];
            i++;
            while (i < lines.length && !/^```/.test(lines[i])) { code.push(lines[i]); i++; }
            i++;
            html += '<pre class="md-pre"><code>' + code.join('\n') + '</code></pre>';
            continue;
        }
        const h = line.match(/^(#{1,6})\s+(.*)$/);
        if (h) { flushPara(); const lvl = h[1].length; html += `<h${lvl}>${inlineMd(h[2])}</h${lvl}>`; i++; continue; }
        if (/^---+$/.test(line)) { flushPara(); html += '<hr>'; i++; continue; }
        if (/^&gt;\s?/.test(line)) { flushPara(); html += '<blockquote>' + inlineMd(line.replace(/^&gt;\s?/, '')) + '</blockquote>'; i++; continue; }
        if (/^\s*[-*]\s+/.test(line)) {
            flushPara();
            const items = [];
            while (i < lines.length && /^\s*[-*]\s+/.test(lines[i])) { items.push('<li>' + inlineMd(lines[i].replace(/^\s*[-*]\s+/, '')) + '</li>'); i++; }
            html += '<ul>' + items.join('') + '</ul>';
            continue;
        }
        if (/^\s*\d+\.\s+/.test(line)) {
            flushPara();
            const items = [];
            while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) { items.push('<li>' + inlineMd(lines[i].replace(/^\s*\d+\.\s+/, '')) + '</li>'); i++; }
            html += '<ol>' + items.join('') + '</ol>';
            continue;
        }
        if (line.trim() === '') { flushPara(); i++; continue; }
        para.push(inlineMd(line));
        i++;
    }
    flushPara();
    return html;
}

function inlineMd(text) {
    return text
        .replace(/`([^`\n]+)`/g, '<code class="md-code">$1</code>')
        .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
        .replace(/\*([^*]+)\*/g, '<em>$1</em>')
        .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
}

// ===================== 列配置渲染 =====================
function renderColumnConfigs() {
    const el = document.getElementById('columnConfigs');
    el.innerHTML = state.columnConfigs.map(col => `
        <div class="col-config-item">
            <input type="checkbox"
                   ${col.visible ? 'checked' : ''}
                   data-key="${col.column_key}"
                   onchange="toggleColumn('${col.column_key}', this.checked)">
            <span>${col.display_name}</span>
        </div>
    `).join('');
}

async function toggleColumn(key, visible) {
    try {
        await apiPut('/column-configs', [{ column_key: key, visible: visible }]);
        state.columnConfigs = state.columnConfigs.map(c =>
            c.column_key === key ? { ...c, visible } : c
        );
        renderResults();
    } catch (e) {
        toast('更新列配置失败', 'error');
    }
}

// ===================== 数据表格渲染 =====================
function renderResults() {
    if (state.groupByFileName) {
        renderGroupedTableHeader();
        renderGroupedTableBody();
    } else {
        renderTableHeader();
        renderTableBody();
    }
    renderPagination();
}

function renderPagination() {
    const countEl = document.getElementById('resultCount');
    if (countEl) {
        if (state.groupByFileName) {
            countEl.textContent = `共 ${state.total} 条记录（${state.totalGroups}个合集），第 ${state.page}/${state.totalPages} 页`;
        } else {
            countEl.textContent = `共 ${state.total} 条记录，第 ${state.page}/${state.totalPages} 页`;
        }
    }

    const prevBtn = document.getElementById('prevPageBtn');
    const nextBtn = document.getElementById('nextPageBtn');
    const pageInfo = document.getElementById('pageInfo');
    const pageSizeInput = document.getElementById('pageSizeInput');

    if (prevBtn) prevBtn.disabled = state.page <= 1;
    if (nextBtn) nextBtn.disabled = state.page >= state.totalPages;
    if (pageInfo) {
        pageInfo.textContent = state.totalPages > 0 ? `${state.page} / ${state.totalPages}` : '0 / 0';
    }
    if (pageSizeInput) {
        pageSizeInput.value = state.pageSize;
        pageSizeInput.onchange = function () {
            const val = parseInt(this.value) || 50;
            const clamped = Math.max(10, Math.min(2000, val));
            if (clamped !== state.pageSize) {
                state.pageSize = clamped;
                state.page = 1;
                loadResults();
            }
            this.value = state.pageSize;
        };
    }
}

function goToPage(p) {
    if (p < 1 || p > state.totalPages) return;
    state.page = p;
    loadResults();
}

/** 跳转到指定页码 */
function jumpToPage() {
    const input = document.getElementById('pageJumpInput');
    if (!input) return;
    const val = parseInt(input.value);
    if (isNaN(val) || val < 1) {
        input.value = '';
        return;
    }
    goToPage(val);
    input.value = '';
}

// 页面跳转输入框回车支持
document.addEventListener('keydown', function (e) {
    if (e.target && e.target.id === 'pageJumpInput' && e.key === 'Enter') {
        jumpToPage();
    }
});

function renderTableHeader() {
    const header = document.getElementById('tableHeader');
    const columns = state.columnConfigs.filter(c => c.visible);

    header.innerHTML = `
        <th style="width:40px;cursor:default;position:relative">
            <input type="checkbox" id="selectAllHeader" ${state.results.length > 0 && state.selectedIds.size === state.results.length ? 'checked' : ''}
                   data-action="selectAll">
        </th>
        <th style="width:32px;position:relative"></th>
        <th style="width:50px;position:relative" data-action="sort" data-col="id">
            ID <span class="sort-icon ${state.sortBy === 'id' ? 'active' : ''}">${state.sortBy === 'id' ? (state.sortOrder === 'desc' ? '▼' : '▲') : '⇅'}</span>
            <span class="col-resizer" data-action="resize"></span>
        </th>
        ${columns.map(col => `
            <th style="position:relative" data-action="sort" data-col="${col.column_key}">
                ${col.display_name}
                <span class="sort-icon ${state.sortBy === col.column_key ? 'active' : ''}">
                    ${state.sortBy === col.column_key ? (state.sortOrder === 'desc' ? '▼' : '▲') : '⇅'}
                </span>
                <span class="col-resizer" data-action="resize"></span>
            </th>
        `).join('')}
        <th style="width:100px;position:relative">操作</th>
    `;

    // 绑定表头事件委托（幂等，仅绑定一次）
    attachTableDelegation();
}

function renderTableBody() {
    const body = document.getElementById('tableBody');
    const columns = state.columnConfigs.filter(c => c.visible);

    if (state.results.length === 0) {
        const colspan = columns.length + 4;
        body.innerHTML = `<tr><td colspan="${colspan}" class="empty-state">暂无数据，请选择扫描配置并执行扫描</td></tr>`;
        body._dataRendered = false;
        return;
    }

    let html = '';
    state.results.forEach(r => {
        const isExpanded = state.expandedIds.has(r.id);
        const isEditing = state.editingIds.has(r.id);
        const editData = state.editData[r.id] || {};
        html += `
        <tr class="${state.selectedIds.has(r.id) ? 'selected' : ''}" data-id="${r.id}">
            <td><input type="checkbox" ${state.selectedIds.has(r.id) ? 'checked' : ''} data-action="select" data-id="${r.id}"></td>
            <td class="expand-cell" data-action="expand" data-id="${r.id}">
                <span class="expand-icon ${isExpanded ? 'expanded' : ''}">▶</span>
            </td>
            <td>${escapeHtml(r.id)}</td>
            ${columns.map(col => {
                let val = isEditing ? (editData[col.column_key] !== undefined ? editData[col.column_key] : getColumnValue(r, col.column_key)) : getColumnValue(r, col.column_key);
                if (isEditing && (col.column_key === 'novel_name' || col.column_key === 'author' || col.column_key === 'protagonist' || col.column_key === 'ending_type')) {
                    return `<td><input class="edit-inline" value="${escapeHtml(val)}" data-edit="${col.column_key}" data-id="${r.id}" onclick="event.stopPropagation()"></td>`;
                } else if (isEditing && (col.column_key === 'summary' || col.column_key === 'features' || col.column_key === 'tags')) {
                    return `<td><input class="edit-inline" value="${escapeHtml(val)}" data-edit="${col.column_key}" data-id="${r.id}" onclick="event.stopPropagation()" placeholder="${col.column_key === 'tags' ? 'JSON数组' : ''}"></td>`;
                }
                return `<td title="${escapeHtml(val)}">${escapeHtml(val)}</td>`;
            }).join('')}
            <td class="action-cell">
                ${isEditing
                    ? `<button class="btn-sm" data-action="saveEdit" data-id="${r.id}">保存</button>
                       <button class="btn-sm" data-action="cancelEdit" data-id="${r.id}">取消</button>`
                    : `<button class="btn-sm" data-action="edit" data-id="${r.id}">编辑</button>
                       <button class="btn-sm danger" data-action="delete" data-id="${r.id}">删除</button>`}
            </td>
        </tr>`;

        if (isExpanded && !isEditing) {
            html += `<tr class="expand-row" data-parent="${r.id}">
                <td colspan="${columns.length + 4}" class="expand-content">
                    <div class="detail-panel">
                        ${buildDetailContent(r)}
                    </div>
                </td>
            </tr>`;
        }
    });

    body.innerHTML = html;
    body._dataRendered = true;

    // 绑定事件委托（幂等，仅绑定一次）
    attachTableDelegation();
}

// ===================== 合集模式渲染 =====================

function renderGroupedTableHeader() {
    const header = document.getElementById('tableHeader');
    const columns = state.columnConfigs.filter(c => c.visible);

    header.innerHTML = `
        <th style="width:40px;cursor:default;position:relative">
            <input type="checkbox" id="selectAllHeader" ${state.groups.length > 0 && state.selectedIds.size === state.total ? 'checked' : ''}
                   data-action="selectAll">
        </th>
        <th style="width:32px;position:relative"></th>
        <th style="width:50px;position:relative">合集</th>
        ${columns.map(col => `
            <th style="position:relative">${col.display_name}</th>
        `).join('')}
        <th style="width:100px;position:relative">操作</th>
    `;

    // 绑定表头事件委托（幂等，仅绑定一次）
    attachTableDelegation();
}

function renderGroupedTableBody() {
    const body = document.getElementById('tableBody');
    const columns = state.columnConfigs.filter(c => c.visible);

    if (state.groups.length === 0) {
        const colspan = columns.length + 4;
        body.innerHTML = `<tr><td colspan="${colspan}" class="empty-state">合集为空：合集按「小说名」聚合，请先在工具栏执行「工程解析 ▾ › 文件名解析」提取书名/作者后查看；若已解析仍为空，可切回列表模式确认是否有数据。</td></tr>`;
        body._dataRendered = false;
        return;
    }

    // 只渲染合集头行，文件行按需懒加载（展开时才插入），大幅降低 DOM 数量
    let html = '';
    state.groups.forEach(group => {
        const groupKey = group.novel_name;
        const isExpanded = state.expandedGroups.has(groupKey);
        const allSelected = group.items.every(item => state.selectedIds.has(item.id));
        const someSelected = group.items.some(item => state.selectedIds.has(item.id));

        html += `
        <tr class="group-header-row" data-group="${escapeHtml(groupKey)}">
            <td>
                <input type="checkbox" class="group-select-all" data-group="${escapeHtml(groupKey)}"
                       ${allSelected ? 'checked' : ''} ${someSelected && !allSelected ? 'data-indeterminate' : ''}>
            </td>
            <td class="group-expand-toggle" data-action="groupToggle" data-group="${escapeHtml(groupKey)}">
                ${isExpanded ? '▼' : '▶'}
            </td>
            <td colspan="${columns.length + 2}" style="padding:6px 12px">
                <div class="group-info">
                    <span class="file-name" title="${escapeHtml(groupKey)}">${escapeHtml(groupKey)}</span>
                    <span class="group-count">${(group.count != null ? group.count : (group.items ? group.items.length : 0))}个文件</span>
                    <span class="group-checked" style="color:var(--accent,#4a90d9);font-weight:500">${group.checked_count ?? 0}个已勾选</span>
                    <span class="group-size">${formatFileSize(group.total_size)}</span>
                </div>
            </td>
        </tr>`;
    });

    body.innerHTML = html;
    body._dataRendered = true;

    // 仅对“已展开”的合集插入其文件行（懒加载）
    state.groups.forEach(group => {
        if (state.expandedGroups.has(group.novel_name)) {
            insertGroupBodyRows(group.novel_name);
        }
    });

    // 绑定事件委托（幂等，仅绑定一次，同时覆盖普通/合集两种模式）
    attachTableDelegation();
}

// 生成单个合集内所有文件行的 HTML（供懒加载使用）
function buildGroupBodyHtml(group, columns) {
    let html = '';
    group.items.forEach(r => {
        const rowSelected = state.selectedIds.has(r.id);
        html += `
        <tr class="group-body-row visible${rowSelected ? ' selected' : ''}" data-id="${r.id}" data-group="${escapeHtml(group.novel_name)}">
            <td><input type="checkbox" ${rowSelected ? 'checked' : ''} data-action="select" data-id="${r.id}"></td>
            <td class="expand-cell" data-action="expand" data-id="${r.id}">
                <span class="expand-icon ${state.expandedIds.has(r.id) ? 'expanded' : ''}">▶</span>
            </td>
            <td>${escapeHtml(r.id)}</td>
            ${columns.map(col => {
                const val = getColumnValue(r, col.column_key);
                return `<td title="${escapeHtml(val)}">${escapeHtml(val)}</td>`;
            }).join('')}
            <td class="action-cell">
                <button class="btn-sm" data-action="edit" data-id="${r.id}">编辑</button>
                <button class="btn-sm danger" data-action="delete" data-id="${r.id}">删除</button>
            </td>
        </tr>`;

        if (state.expandedIds.has(r.id)) {
            html += `<tr class="expand-row" data-parent="${r.id}">
                <td colspan="${columns.length + 4}" class="expand-content">
                    <div class="detail-panel">${buildDetailContent(r)}</div>
                </td>
            </tr>`;
        }
    });
    return html;
}

// 懒加载：在指定合集头行后插入其文件行（已插入则跳过，避免重复）
function insertGroupBodyRows(groupName) {
    const body = document.getElementById('tableBody');
    const headerRow = body.querySelector(`tr.group-header-row[data-group="${cssEscapeAttr(groupName)}"]`);
    if (!headerRow) return;
    // 已渲染则跳过
    const next = headerRow.nextElementSibling;
    if (next && next.classList.contains('group-body-row') && next.dataset.group === groupName) return;

    const group = state.groups.find(g => g.novel_name === groupName);
    if (!group) return;
    const columns = state.columnConfigs.filter(c => c.visible);
    const tpl = document.createElement('template');
    tpl.innerHTML = buildGroupBodyHtml(group, columns);
    headerRow.parentNode.insertBefore(tpl.content, headerRow.nextSibling);
}

// 懒加载：移除指定合集头行后的全部文件行（折叠时调用）
function removeGroupBodyRows(groupName) {
    const body = document.getElementById('tableBody');
    const headerRow = body.querySelector(`tr.group-header-row[data-group="${cssEscapeAttr(groupName)}"]`);
    if (!headerRow) return;
    let node = headerRow.nextElementSibling;
    while (node && !(node.classList && node.classList.contains('group-header-row'))) {
        const next = node.nextElementSibling;
        node.remove();
        node = next;
    }
}

// 折叠/展开合集：仅操作当前合集的 DOM，不再全表重渲染
function toggleGroup(groupName) {
    const body = document.getElementById('tableBody');
    const headerRow = body.querySelector(`tr.group-header-row[data-group="${cssEscapeAttr(groupName)}"]`);
    if (!headerRow) return;
    const iconEl = headerRow.querySelector('.group-expand-toggle');
    if (state.expandedGroups.has(groupName)) {
        state.expandedGroups.delete(groupName);
        removeGroupBodyRows(groupName);
        if (iconEl) iconEl.textContent = '▶';
    } else {
        state.expandedGroups.add(groupName);
        insertGroupBodyRows(groupName);
        if (iconEl) iconEl.textContent = '▼';
    }
}

// 安全转义 CSS 属性选择器中的值（兼容含引号/特殊字符的小说名）
function cssEscapeAttr(value) {
    if (window.CSS && typeof CSS.escape === 'function') {
        return CSS.escape(value);
    }
    return String(value).replace(/"/g, '\\"');
}

function formatFileSize(bytes) {
    if (!bytes || bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const k = 1024;
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    const size = (bytes / Math.pow(k, i)).toFixed(i > 0 ? 1 : 0);
    return size + ' ' + units[i];
}

function toggleGroupSelectAll(checked) {
    // 全选/取消全选所有合集的所有文件
    state.groups.forEach(group => {
        group.items.forEach(item => {
            if (checked) {
                state.selectedIds.add(item.id);
            } else {
                state.selectedIds.delete(item.id);
            }
        });
    });
    // 直接更新 DOM  checkbox 状态，不重绘整个表格
    const body = document.getElementById('tableBody');
    body.querySelectorAll('input[type="checkbox"]').forEach(cb => {
        if (cb.dataset.action === 'selectAll') return; // 跳过全选checkbox
        cb.checked = checked;
    });
    body.querySelectorAll('tr.group-body-row').forEach(tr => {
        tr.classList.toggle('selected', checked);
    });
    updateHeaderCheckbox();
}

function toggleSingleGroupSelectAll(groupName, checked) {
    const group = state.groups.find(g => g.novel_name === groupName);
    if (!group) return;
    group.items.forEach(item => {
        if (checked) {
            state.selectedIds.add(item.id);
        } else {
            state.selectedIds.delete(item.id);
        }
    });
    // 直接更新 DOM 中该组的 checkbox 状态，不重绘整个表格
    const body = document.getElementById('tableBody');
    body.querySelectorAll('tr[data-group]').forEach(tr => {
        if (tr.dataset.group === groupName) {
            const cb = tr.querySelector('input[type="checkbox"]');
            if (cb) cb.checked = checked;
            if (tr.classList.contains('group-body-row')) {
                tr.classList.toggle('selected', checked);
            }
        }
    });
    updateHeaderCheckbox();
}

function buildDetailContent(r) {
    const sections = [];
    // 使用后端预解析的 tags_list，避免前端 JSON.parse
    const tagsArr = r.tags_list || [];
    if (tagsArr.length > 0) {
        sections.push(`<div class="detail-section">
            <div class="detail-label">标签</div>
            <div class="detail-value">${tagsArr.map(t => `<span class="tag">${escapeHtml(t)}</span>`).join(' ')}</div>
        </div>`);
    }
    const fields = [
        { label: '作者', value: r.author },
        { label: '主角', value: r.protagonist },
        { label: '进度', value: r.progress },
        { label: '来源', value: r.source },
        { label: '结局类型', value: r.ending_type },
    ];
    fields.forEach(f => {
        if (f.value) {
            sections.push(`<div class="detail-section">
                <div class="detail-label">${f.label}</div>
                <div class="detail-value">${escapeHtml(f.value)}</div>
            </div>`);
        }
    });
    const textFields = [
        { label: '内容简介', key: 'summary' },
        { label: '核心亮点', key: 'features' },
        { label: '重要配角', key: 'supporting_roles' },
        { label: '世界观设定', key: 'world_building' },
        { label: '结局分析', key: 'ending' },
    ];
    textFields.forEach(f => {
        const val = r[f.key];
        if (val) {
            sections.push(`<div class="detail-section">
                <div class="detail-label">${f.label}</div>
                <div class="detail-value text-content">${escapeHtml(val)}</div>
            </div>`);
        }
    });
    if (sections.length === 0) {
        return '<div class="detail-empty">暂无解析数据</div>';
    }
    return sections.join('');
}

function getColumnValue(row, key) {
    // 优先使用后端预计算字段，减少前端解析/格式化/截断开销
    switch (key) {
        case 'file_name': return row.file_name;
        case 'file_size': return row.file_size_display || '';
        case 'file_path': return row.file_path;
        case 'created_date': return row.created_date || '';
        case 'novel_name': return row.novel_name || '';
        case 'author': return row.author || '';
        case 'tags': return row.tags_display || '';
        case 'summary': return truncateText(row.summary || '', 60);
        case 'features': return truncateText(row.features || '', 60);
        case 'protagonist': return row.protagonist || '';
        case 'ending_type': return row.ending_type || '';
        case 'progress': return row.progress || '';
        case 'source': return row.source || '';
        default: return '';
    }
}

function truncateText(str, maxLen) {
    if (!str || str.length <= maxLen) return str || '';
    return str.substring(0, maxLen) + '...';
}

// ===================== 折叠展开 =====================
function toggleExpand(id) {
    const wasExpanded = state.expandedIds.has(id);
    if (wasExpanded) {
        state.expandedIds.delete(id);
        const row = document.querySelector(`#tableBody tr.expand-row[data-parent="${id}"]`);
        if (row) row.remove();
        const icon = document.querySelector(`#tableBody tr[data-id="${id}"] .expand-icon`);
        if (icon) icon.classList.remove('expanded');
    } else {
        state.expandedIds.add(id);
        const mainRow = document.querySelector(`#tableBody tr[data-id="${id}"]`);
        if (!mainRow) return;
        const columns = state.columnConfigs.filter(c => c.visible);
        const colspan = columns.length + 4;
        const expandTr = document.createElement('tr');
        expandTr.className = 'expand-row';
        expandTr.dataset.parent = id;
        expandTr.innerHTML = `<td colspan="${colspan}">${buildDetailContent(findRowById(id))}</td>`;
        mainRow.insertAdjacentElement('afterend', expandTr);
        const icon = mainRow.querySelector('.expand-icon');
        if (icon) icon.classList.add('expanded');
    }
}

// ===================== 排序（三次恢复默认） =====================
const DEFAULT_SORT = { sortBy: 'id', sortOrder: 'desc' };

function sortByColumn(key) {
    // Initialize click count
    if (state.sortClicks[key] === undefined) {
        state.sortClicks[key] = 0;
    }
    state.sortClicks[key]++;

    const clickCount = state.sortClicks[key];

    if (clickCount === 1) {
        // First click: asc
        state.sortBy = key;
        state.sortOrder = 'asc';
        state.page = 1;
    } else if (clickCount === 2) {
        // Second click: desc
        state.sortBy = key;
        state.sortOrder = 'desc';
        state.page = 1;
    } else {
        // Third click: reset to default, reset counter
        state.sortBy = DEFAULT_SORT.sortBy;
        state.sortOrder = DEFAULT_SORT.sortOrder;
        state.sortClicks[key] = 0;
        // Reset all other columns too
        Object.keys(state.sortClicks).forEach(k => {
            if (k !== key) state.sortClicks[k] = 0;
        });
    }

    loadResults();
}

// ===================== 列宽拖拽 =====================
let resizeTarget = null;
let resizeStartX = 0;
let resizeStartW = 0;
let resizeRAF = null;
let resizeNewWidth = 0;

function startResize(e, handle) {
    e.stopPropagation();
    e.preventDefault();
    const th = handle.parentElement;
    resizeTarget = th;
    resizeStartX = e.clientX;
    resizeStartW = th.offsetWidth;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
    document.addEventListener('mousemove', doResize);
    document.addEventListener('mouseup', stopResize);
}

function doResize(e) {
    if (!resizeTarget) return;
    const diff = e.clientX - resizeStartX;
    resizeNewWidth = Math.max(30, resizeStartW + diff);
    // 用 requestAnimationFrame 节流，避免每次 mousemove 都触发布局重算
    if (resizeRAF) return;
    resizeRAF = requestAnimationFrame(() => {
        resizeRAF = null;
        if (resizeTarget) resizeTarget.style.width = resizeNewWidth + 'px';
    });
}

function stopResize() {
    if (resizeRAF) { cancelAnimationFrame(resizeRAF); resizeRAF = null; }
    resizeTarget = null;
    document.body.style.cursor = '';
    document.body.style.userSelect = '';
    document.removeEventListener('mousemove', doResize);
    document.removeEventListener('mouseup', stopResize);
}

// ===================== 选择操作 =====================
function toggleSelect(id) {
    if (state.selectedIds.has(id)) {
        state.selectedIds.delete(id);
    } else {
        state.selectedIds.add(id);
    }
    // 只切换行高亮，不重渲染整个表格
    const tr = document.querySelector(`#tableBody tr[data-id="${id}"]`);
    if (tr) tr.classList.toggle('selected');
    updateHeaderCheckbox();
}

function toggleSelectAll(event) {
    const checked = event.target.checked;
    if (state.groupByFileName) {
        // 合集模式：全选/取消全选当前页所有文件
        state.groups.forEach(group => {
            group.items.forEach(item => {
                if (checked) {
                    state.selectedIds.add(item.id);
                } else {
                    state.selectedIds.delete(item.id);
                }
            });
        });
        // 直接更新 DOM，不重绘整个表格
        document.querySelectorAll('#tableBody input[type="checkbox"]').forEach(cb => {
            if (cb.dataset.action === 'selectAll') return;
            cb.checked = checked;
        });
        document.querySelectorAll('#tableBody tr.group-body-row').forEach(tr => {
            tr.classList.toggle('selected', checked);
        });
    } else {
        if (checked) {
            state.selectedIds = new Set(state.results.map(r => r.id));
        } else {
            state.selectedIds.clear();
        }
        // 批量切换所有行的选中类和复选框
        document.querySelectorAll('#tableBody tr[data-id]').forEach(tr => {
            const id = Number(tr.dataset.id);
            const selected = state.selectedIds.has(id);
            tr.classList.toggle('selected', selected);
            const cb = tr.querySelector('input[type="checkbox"]');
            if (cb) cb.checked = selected;
        });
    }
    updateHeaderCheckbox();
}

function updateHeaderCheckbox() {
    const cb = document.querySelector('#tableHeader input[type="checkbox"]');
    if (state.groupByFileName) {
        // 合集模式：按当前页所有文件计算
        const totalItems = state.groups.reduce((sum, g) => sum + g.items.length, 0);
        if (cb && totalItems > 0) {
            cb.checked = state.selectedIds.size === totalItems;
            cb.indeterminate = state.selectedIds.size > 0 && state.selectedIds.size < totalItems;
        }
        const toolbarCb = document.getElementById('selectAll');
        if (toolbarCb && totalItems > 0) {
            toolbarCb.checked = state.selectedIds.size === totalItems;
        }
    } else {
        if (cb && state.results.length > 0) {
            cb.checked = state.selectedIds.size === state.results.length;
            cb.indeterminate = state.selectedIds.size > 0 && state.selectedIds.size < state.results.length;
        }
        // 同步工具栏的全选复选框
        const toolbarCb = document.getElementById('selectAll');
        if (toolbarCb && state.results.length > 0) {
            toolbarCb.checked = state.selectedIds.size === state.results.length;
        }
    }
}

// ===================== 事件委托（表格操作，统一处理普通/合集两种模式） =====================

// 按 id 查找行数据：合集模式下数据在 state.groups 中，需在两种来源中查找
function findRowById(id) {
    let row = state.results.find(r => r.id === id);
    if (row) return row;
    for (const g of state.groups) {
        const found = (g.items || []).find(it => it.id === id);
        if (found) return found;
    }
    return undefined;
}

// 事件委托只绑定一次（幂等），兼容普通列表与合集两种渲染
function attachTableDelegation() {
    const header = document.getElementById('tableHeader');
    const body = document.getElementById('tableBody');
    if (header && !header._delegationAttached) {
        header._delegationAttached = true;
        header.addEventListener('click', handleHeaderClick);
        header.addEventListener('change', handleHeaderChange);
    }
    if (body && !body._delegationAttached) {
        body._delegationAttached = true;
        body.addEventListener('click', handleBodyClick);
        body.addEventListener('change', handleBodyChange);
    }
}

function handleHeaderClick(e) {
    const th = e.target.closest('th');
    if (!th) return;
    // 列宽拖拽手柄优先（避免被 th 的排序 action 误判）
    const handle = e.target.closest('.col-resizer');
    if (handle) {
        startResize(e, handle);
        return;
    }
    const action = th.dataset.action;
    if (action === 'sort') {
        sortByColumn(th.dataset.col);
    }
    // 全选只在 change 中处理，避免 click+change 双触发互相抵消
}

function handleHeaderChange(e) {
    if (e.target.dataset.action === 'selectAll') {
        if (state.groupByFileName) toggleGroupSelectAll(e.target.checked);
        else toggleSelectAll(e);
    }
}

function handleBodyClick(e) {
    const target = e.target;
    const action = target.dataset.action;

    // 合集折叠/展开（仅操作当前合集，不重绘全表）
    if (action === 'groupToggle') {
        toggleGroup(target.dataset.group);
        return;
    }
    // 排序（表头委托，普通模式）
    if (action === 'sort') {
        sortByColumn(target.dataset.col);
        return;
    }
    // 列宽拖拽
    if (action === 'resize') {
        startResize(e, target);
        return;
    }
    // 全选
    if (action === 'selectAll') {
        if (state.groupByFileName) toggleGroupSelectAll(target.checked);
        else toggleSelectAll(e);
        return;
    }
    // 选择单行
    if (action === 'select') {
        const id = Number(target.dataset.id);
        toggleSelect(id);
        target.checked = state.selectedIds.has(id);
        return;
    }
    // 展开详情
    if (action === 'expand') {
        toggleExpand(Number(target.dataset.id));
        return;
    }
    // 删除
    if (action === 'delete') {
        deleteSingle(Number(target.dataset.id));
        return;
    }
    // 编辑
    if (action === 'edit') {
        startEdit(Number(target.dataset.id));
        return;
    }
    // 保存编辑
    if (action === 'saveEdit') {
        saveEdit(Number(target.dataset.id));
        return;
    }
    // 取消编辑
    if (action === 'cancelEdit') {
        cancelEdit(Number(target.dataset.id));
        return;
    }
}

function handleBodyChange(e) {
    const target = e.target;
    if (target.classList.contains('group-select-all')) {
        toggleSingleGroupSelectAll(target.dataset.group, target.checked);
        return;
    }
    if (target.dataset.action === 'selectAll') {
        if (state.groupByFileName) toggleGroupSelectAll(target.checked);
        else toggleSelectAll(e);
    }
}

// ===================== 行内编辑 =====================

function startEdit(id) {
    state.editingIds.add(id);
    const row = findRowById(id);
    if (!row) return;
    // 初始化编辑数据
    state.editData[id] = {};
    ['novel_name', 'author', 'tags', 'summary', 'features', 'protagonist', 'ending_type', 'progress', 'source'].forEach(k => {
        state.editData[id][k] = getRawColumnValue(row, k);
    });
    // 重新渲染该行及展开行
    reRenderRow(id);
}

function reRenderRow(id) {
    const body = document.getElementById('tableBody');
    const columns = state.columnConfigs.filter(c => c.visible);
    const r = findRowById(id);
    if (!r) return;

    const isEditing = state.editingIds.has(id);
    const isExpanded = state.expandedIds.has(id);
    const editData = state.editData[id] || {};

    // 移除现有行和展开行
    const oldTr = body.querySelector(`tr[data-id="${id}"]`);
    const oldExpandTr = body.querySelector(`tr.expand-row[data-parent="${id}"]`);
    if (oldExpandTr) oldExpandTr.remove();
    if (!oldTr) return;

    const tr = document.createElement('tr');
    tr.className = state.selectedIds.has(id) ? 'selected' : '';
    tr.dataset.id = id;

    let tdHtml = `
        <td><input type="checkbox" ${state.selectedIds.has(id) ? 'checked' : ''} data-action="select" data-id="${id}"></td>
        <td class="expand-cell" data-action="expand" data-id="${id}">
            <span class="expand-icon ${isExpanded && !isEditing ? 'expanded' : ''}">▶</span>
        </td>
        <td>${escapeHtml(id)}</td>`;

    columns.forEach(col => {
        let val = isEditing ? (editData[col.column_key] !== undefined ? editData[col.column_key] : getRawColumnValue(r, col.column_key)) : getColumnValue(r, col.column_key);
        if (isEditing) {
            if (['novel_name', 'author', 'protagonist', 'ending_type', 'progress', 'source'].includes(col.column_key)) {
                tdHtml += `<td><input class="edit-inline" value="${escapeHtml(val)}" data-edit="${col.column_key}" data-id="${id}"></td>`;
            } else if (['summary', 'features', 'tags'].includes(col.column_key)) {
                tdHtml += `<td><input class="edit-inline" value="${escapeHtml(val)}" data-edit="${col.column_key}" data-id="${id}" placeholder="${col.column_key === 'tags' ? 'JSON数组' : ''}"></td>`;
            } else {
                tdHtml += `<td title="${escapeHtml(val)}">${escapeHtml(val)}</td>`;
            }
        } else {
            tdHtml += `<td title="${escapeHtml(val)}">${escapeHtml(val)}</td>`;
        }
    });

    tdHtml += `<td class="action-cell">
        ${isEditing
            ? `<button class="btn-sm" data-action="saveEdit" data-id="${id}">保存</button>
               <button class="btn-sm" data-action="cancelEdit" data-id="${id}">取消</button>`
            : `<button class="btn-sm" data-action="edit" data-id="${id}">编辑</button>
               <button class="btn-sm danger" data-action="delete" data-id="${id}">删除</button>`}
    </td>`;

    tr.innerHTML = tdHtml;
    oldTr.replaceWith(tr);

    // 展开行（编辑模式下不显示展开）
    if (isExpanded && !isEditing) {
        const colspan = columns.length + 4;
        const expandTr = document.createElement('tr');
        expandTr.className = 'expand-row';
        expandTr.dataset.parent = id;
        expandTr.innerHTML = `<td colspan="${colspan}"><div class="detail-panel">${buildDetailContent(r)}</div></td>`;
        tr.insertAdjacentElement('afterend', expandTr);
    }
}

function cancelEdit(id) {
    state.editingIds.delete(id);
    delete state.editData[id];
    reRenderRow(id);
}

async function saveEdit(id) {
    try {
        // 从编辑数据中只提取支持的字段
        const rawData = state.editData[id];
        if (!rawData) {
            toast('保存失败: 编辑数据丢失，请重新编辑', 'error');
            return;
        }
        // 收集输入框的值
        const tr = document.querySelector(`#tableBody tr[data-id="${id}"]`);
        if (tr) {
            tr.querySelectorAll('input[data-edit]').forEach(inp => {
                rawData[inp.dataset.edit] = inp.value;
            });
        }
        // 只发送后端支持的字段，过滤掉空字符串
        const data = {};
        ['novel_name', 'author', 'tags', 'summary', 'features', 'protagonist', 'ending_type', 'progress', 'source'].forEach(k => {
            if (rawData[k] !== undefined) {
                data[k] = rawData[k];
            }
        });
        await apiPut(`/results/${id}`, data);
        toast('保存成功', 'success');
        state.editingIds.delete(id);
        delete state.editData[id];
        // 更新本地数据
        const row = findRowById(id);
        if (row) {
            Object.assign(row, data);
        }
        reRenderRow(id);
    } catch (e) {
        console.error('保存失败:', e);
        toast('保存失败: ' + e.message, 'error');
    }
}

function getRawColumnValue(r, key) {
    switch (key) {
        case 'file_name': return r.file_name || '';
        case 'novel_name': return r.novel_name || '';
        case 'author': return r.author || '';
        case 'tags':
            // 优先使用原始 JSON，否则用后端预解析列表格式化
            if (r.tags_list && r.tags_list.length > 0) {
                return JSON.stringify(r.tags_list, null, 2);
            }
            return r.tags || '';
        case 'summary': return r.summary || '';
        case 'features': return r.features || '';
        case 'protagonist': return r.protagonist || '';
        case 'ending_type': return r.ending_type || '';
        case 'progress': return r.progress || '';
        case 'source': return r.source || '';
        default: return '';
    }
}

// ===================== 解析进度（异步+进度条） =====================

let parseTaskTimer = null;
let currentParseTaskId = null;
let lastParseLogSig = '';

function showParseProgress(show) {
    document.getElementById('parseProgress').style.display = show ? 'block' : 'none';
    if (!show) {
        currentParseTaskId = null;
        sessionStorage.removeItem('parseTaskId');
        lastParseLogSig = '';
    }
}

function updateParseProgress(taskInfo) {
    const pct = taskInfo.total > 0 ? Math.round(taskInfo.processed / taskInfo.total * 100) : 0;
    document.getElementById('parseProgressDesc').textContent = taskInfo.description || '解析中...';
    document.getElementById('parseProgressCount').textContent = `${taskInfo.processed}/${taskInfo.total}`;
    document.getElementById('parseProgressBar').style.width = pct + '%';

    // 显示已用时间
    const elapsedEl = document.getElementById('parseElapsed');
    if (taskInfo.elapsed !== undefined && elapsedEl) {
        const seconds = Math.floor(taskInfo.elapsed);
        const m = Math.floor(seconds / 60);
        const s = seconds % 60;
        elapsedEl.textContent = `${m}分${s}秒`;
    } else if (elapsedEl) {
        elapsedEl.textContent = '';
    }

    // 显示日志（仅在内容变化时才重建 DOM）
    const logPanel = document.getElementById('parseLogPanel');
    if (taskInfo.logs && taskInfo.logs.length > 0 && logPanel) {
        const last = taskInfo.logs[taskInfo.logs.length - 1];
        const sig = taskInfo.logs.length + '|' + (last ? last.time + ':' + last.msg : '');
        if (sig !== lastParseLogSig) {
            lastParseLogSig = sig;
            logPanel.innerHTML = taskInfo.logs.map(log => {
                const level = log.level || 'info';
                return `<div class="parse-log-entry"><span class="log-time">${escapeHtml(log.time)}</span><span class="log-level-${level}">${escapeHtml(log.msg)}</span></div>`;
            }).join('');
            logPanel.scrollTop = logPanel.scrollHeight;
        }
    }

    // 运行中显示取消按钮，否则隐藏
    const cancelBtn = document.getElementById('parseCancelBtn');
    if (cancelBtn) {
        cancelBtn.style.display = taskInfo.status === 'running' ? 'inline-block' : 'none';
    }
}

async function cancelParseTask() {
    if (!currentParseTaskId) return;
    if (!confirm('确定取消当前的解析任务？')) return;
    try {
        await apiPost(`/parse-cancel/${currentParseTaskId}`);
        toast('正在取消解析任务...', 'info');
        document.getElementById('parseCancelBtn').disabled = true;
    } catch (e) {
        toast('取消失败: ' + e.message, 'error');
    }
}

// 等待指定解析任务完成（Promise），复用解析进度条 UI；用于「扫描时同步解析」流程。
// resolve(true)=成功完成, resolve(false)=取消/失败/出错。
function awaitParseTask(taskId) {
    return new Promise((resolve) => {
        async function tick() {
            try {
                const info = await apiGet(`/parse-tasks/${taskId}`);
                updateParseProgress(info);
                if (info.status === 'running') {
                    setTimeout(tick, 1500);
                } else if (info.status === 'done') {
                    const r = info.result || {};
                    const failTxt = r.failed ? `，失败${r.failed}个` : '';
                    toast(`工程类解析完成: 共${r.total}个，成功${r.success}个${failTxt}`, r.failed ? 'warning' : 'success');
                    resolve(true);
                } else {
                    toast('工程类解析: ' + (info.message || info.status), 'warning');
                    resolve(false);
                }
            } catch (e) {
                toast('获取解析进度失败: ' + e.message, 'error');
                resolve(false);
            }
        }
        tick();
    });
}

async function pollParseTask(taskId) {
    currentParseTaskId = taskId;
    sessionStorage.setItem('parseTaskId', taskId);
    try {
        const info = await apiGet(`/parse-tasks/${taskId}`);
        showParseProgress(true);
        updateParseProgress(info);

        if (info.status === 'running') {
            parseTaskTimer = setTimeout(() => pollParseTask(taskId), 1500);
        } else {
            clearTimeout(parseTaskTimer);
            parseTaskTimer = null;
            setTimeout(() => showParseProgress(false), 2000);

            if (info.status === 'done') {
                const r = info.result || {};
                const skippedText = r.skipped ? `，跳过${r.skipped}个` : '';
                if (r.failed > 0) {
                    toast(`解析完成: 共${r.total}个，成功${r.success}个${skippedText}，失败${r.failed}个`, 'warning');
                } else {
                    toast(`解析完成: 共${r.total}个，全部成功${skippedText}`, 'success');
                }
            } else if (info.status === 'cancelled') {
                const r = info.result || {};
                toast(`解析已取消: 已处理${r.total || 0}个`, 'warning');
            } else if (info.status === 'error') {
                toast('解析失败: ' + (info.message || '未知错误'), 'error');
            }

            await loadResults();
            await updateStats(true);
        }
    } catch (e) {
        clearTimeout(parseTaskTimer);
        parseTaskTimer = null;
        showParseProgress(false);
        toast('获取解析进度失败: ' + e.message, 'error');
    }
}

// ===================== 工程方法（正则）文件名解析 =====================
async function startRegexParseName(fetchAll = false, force = false) {
    let url, desc;
    if (fetchAll) {
        if (!state.currentConfigId) {
            toast('请先选择一个扫描配置', 'warning');
            return;
        }
        const msg = force
            ? '确定要强制重跑全部工程文件名解析？（将忽略已有解析数据，重新解析所有文件，不消耗API额度）'
            : '确定对当前扫描配置下的所有文件进行工程文件名解析？\n（仅根据文件名格式提取小说名和作者，不消耗API额度）';
        if (!confirm(msg)) return;
        url = `/parse-name-regex-all/${state.currentConfigId}`;
        if (force) url += '?force=true';
        desc = force ? '全部强制重跑文件名解析' : '全部工程文件名解析';
    } else {
        if (state.selectedIds.size === 0) {
            toast('请先选择要解析的文件', 'warning');
            return;
        }
        if (!confirm(`确定对 ${state.selectedIds.size} 个文件进行工程文件名解析？`)) return;
        const params = new URLSearchParams();
        state.selectedIds.forEach(id => params.append('file_ids', id));
        url = '/parse-name-regex?' + params.toString();
        desc = '工程文件名解析';
    }

    try {
        const result = await apiPost(url);
        if (result.task_id) {
            pollParseTask(result.task_id);
            toast(`${desc}已启动，查看进度条...`, 'info');
        }
    } catch (e) {
        toast(`${desc}启动失败: ` + e.message, 'error');
    }
}

// ===================== 工程方法（正则）摘要提取 =====================
async function startRegexParseSummary(fetchAll = false, force = false) {
    let url, desc;
    if (fetchAll) {
        if (!state.currentConfigId) {
            toast('请先选择一个扫描配置', 'warning');
            return;
        }
        const msg = force
            ? '确定要强制重跑全部工程摘要提取？（将忽略已有摘要数据，重新提取所有文件摘要，不消耗API额度）'
            : '确定对当前扫描配置下的所有文件进行工程摘要提取？\n（读取文件内容，提取首章前的简介，不消耗API额度）';
        if (!confirm(msg)) return;
        url = `/parse-summary-regex-all/${state.currentConfigId}`;
        if (force) url += '?force=true';
        desc = force ? '全部强制重跑摘要解析' : '全部工程摘要解析';
    } else {
        if (state.selectedIds.size === 0) {
            toast('请先选择要解析的文件', 'warning');
            return;
        }
        if (!confirm(`确定对 ${state.selectedIds.size} 个文件进行工程摘要提取？`)) return;
        const params = new URLSearchParams();
        state.selectedIds.forEach(id => params.append('file_ids', id));
        url = '/parse-summary-regex?' + params.toString();
        desc = '工程摘要解析';
    }

    try {
        const result = await apiPost(url);
        if (result.task_id) {
            pollParseTask(result.task_id);
            toast(`${desc}已启动，查看进度条...`, 'info');
        }
    } catch (e) {
        toast(`${desc}启动失败: ` + e.message, 'error');
    }
}

// ===================== 导出 Markdown =====================
async function exportMarkdown(fetchAll = false) {
    // 导出整个配置（对齐 Excel 行为）
    if (fetchAll) {
        if (!state.currentConfigId) {
            toast('请先选择一个扫描配置', 'warning');
            return;
        }
        if (!confirm('确定导出当前配置下的所有记录到Markdown？')) return;
        try {
            const result = await apiPost(`/export-md?config_id=${state.currentConfigId}`);
            if (result.files && result.files.length > 0) {
                alert(`成功导出 ${result.files.length} 个Markdown文件\n目录: ${result.directory}\n\n文件列表:\n${result.files.map(f => '  ' + f.file_name).join('\n')}`);
                toast(`全部导出成功: ${result.files.length} 个文件`, 'success');
            } else {
                toast('当前配置无数据可导出', 'warning');
            }
        } catch (e) {
            toast('导出全部MD失败: ' + e.message, 'error');
        }
        return;
    }

    if (state.selectedIds.size === 0) {
        toast('请先选择要导出的文件', 'warning');
        return;
    }
    try {
        const params = new URLSearchParams();
        state.selectedIds.forEach(id => params.append('ids', id));
        const result = await apiPost('/export-md?' + params.toString());
        if (result.files && result.files.length > 0) {
            alert(`成功导出 ${result.files.length} 个Markdown文件\n目录: ${result.directory}\n\n文件列表:\n${result.files.map(f => '  ' + f.file_name).join('\n')}`);
            toast(`成功导出 ${result.files.length} 个文件`, 'success');
        } else {
            toast('导出完成，但没有生成文件', 'warning');
        }
    } catch (e) {
        toast('导出失败: ' + e.message, 'error');
    }
}

// ===================== 导出 Excel =====================

async function exportExcel(fetchAll = false) {
    if (fetchAll) {
        if (!state.currentConfigId) {
            toast('请先选择一个扫描配置', 'warning');
            return;
        }
        if (!confirm('确定导出当前配置下的所有记录到Excel？')) return;
        try {
            const result = await apiPost(`/export-excel?config_id=${state.currentConfigId}`);
            if (result.file_name) {
                toast(`全部导出成功: ${result.file_name}（${result.exported_count}条）`, 'success');
                window.open(`/exports/${result.file_name}`);
            } else {
                toast('导出失败: ' + (result.message || '未知错误'), 'error');
            }
        } catch (e) {
            toast('导出全部Excel失败: ' + e.message, 'error');
        }
        return;
    }

    if (state.selectedIds.size === 0) {
        toast('请先选择要导出的记录', 'warning');
        return;
    }
    
    if (!confirm(`确定导出 ${state.selectedIds.size} 条记录到Excel？`)) return;
    
    try {
        const ids = Array.from(state.selectedIds);
        const params = new URLSearchParams();
        ids.forEach(id => params.append('ids', id));
        const result = await apiPost('/export-excel?' + params.toString());
        
        if (result.file_name) {
            toast(`Excel导出成功: ${result.file_name}（${result.exported_count}条）`, 'success');
            const exportPath = result.directory.replace(/\\/g, '/');
            window.open(`/exports/${result.file_name}`);
        } else {
            toast('导出失败: ' + (result.message || '未知错误'), 'error');
        }
    } catch (e) {
        toast('导出Excel失败: ' + e.message, 'error');
    }
}

// ===================== 删除操作 =====================
let deleteClearMode = false;

function showDeleteModal(message, ids) {
    document.getElementById('deleteMessage').textContent = message;
    document.getElementById('deleteTargetIds').value = ids.join(',');
    document.getElementById('deleteModal').style.display = 'flex';
}

// ===================== 删除进度条 =====================
function showDeleteProgress() {
    const opts = document.querySelector('#deleteModal .delete-options');
    const footer = document.querySelector('#deleteModal .modal-footer');
    if (opts) opts.style.display = 'none';
    if (footer) footer.style.display = 'none';
    const msg = document.getElementById('deleteMessage');
    if (msg) msg.textContent = '正在删除，请稍候...';
    const prog = document.getElementById('deleteProgress');
    if (prog) prog.style.display = 'block';
    updateDeleteProgress(0, 1);
}

function updateDeleteProgress(done, total) {
    const pct = total > 0 ? Math.round((done / total) * 100) : 100;
    const bar = document.getElementById('deleteProgressBar');
    const txt = document.getElementById('deleteProgressText');
    if (bar) bar.style.width = pct + '%';
    if (txt) txt.textContent = `已处理 ${done} / ${total}（${pct}%）`;
}

function hideDeleteProgress() {
    const opts = document.querySelector('#deleteModal .delete-options');
    const footer = document.querySelector('#deleteModal .modal-footer');
    if (opts) opts.style.display = '';
    if (footer) footer.style.display = '';
    const msg = document.getElementById('deleteMessage');
    if (msg) msg.textContent = '';
    const prog = document.getElementById('deleteProgress');
    if (prog) prog.style.display = 'none';
}

async function confirmDeleteAction() {
    try {
        const mode = document.querySelector('input[name="deleteMode"]:checked')?.value;
        const idsStr = document.getElementById('deleteTargetIds').value;
        const ids = idsStr.split(',').filter(Boolean);
        if (ids.length === 0) {
            toast('没有可删除的记录', 'warning');
            closeModal('deleteModal');
            return;
        }
        // 显示进度条，删除过程中保持弹框打开
        showDeleteProgress();
        console.log(`[删除操作] IDs=${idsStr}, mode=${mode}, withFiles=${mode === 'file'}`);
        if (deleteClearMode) {
            deleteClearMode = false;
            await executeClearAll(mode === 'file');
        } else {
            await executeDelete(ids, mode === 'file');
        }
    } catch (e) {
        console.error('[删除操作] 出错:', e);
        toast('删除操作出错: ' + e.message, 'error');
    } finally {
        hideDeleteProgress();
        closeModal('deleteModal');
    }
}

async function executeClearAll(withFiles) {
    if (!state.currentConfigId) {
        toast('未选择扫描配置', 'warning');
        return;
    }
    try {
        updateDeleteProgress(0, 1);
        const result = await apiDelete(`/configs/${state.currentConfigId}/clear?with_files=${withFiles}`);
        updateDeleteProgress(1, 1);
        toast(result.message, 'success');
        state.selectedIds.clear();
        state.page = 1;
    } catch (e) {
        toast('清空失败: ' + e.message, 'error');
        return;
    }
    // 清空成功后强制刷新列表：先清空当前数据让页面立即响应，再重新拉取
    state.results = [];
    state.total = 0;
    state.totalPages = 0;
    state.expandedIds.clear();
    state.editingIds.clear();
    state.editData = {};
    renderResults();
    try {
        await loadResults();
        await updateStats(true);
    } catch (e) {
        toast('列表刷新失败，请手动刷新', 'warning');
    }
    // 清空后重建合集（展示进度条）
    try {
        await rebuildGroups(state.currentConfigId);
    } catch (_) { /* 合集重建失败不阻断主流程 */ }
}

async function executeDelete(ids, withFiles) {
    const endpoint = withFiles ? '/results/with-files' : '/results';
    const total = ids.length;
    // 删除源文件（物理删除）较慢，用小批次让进度条更平滑
    const BATCH = withFiles ? 20 : 100;
    let done = 0;
    let failed = 0;
    try {
        for (let i = 0; i < total; i += BATCH) {
            const batch = ids.slice(i, i + BATCH);
            const params = new URLSearchParams();
            batch.forEach(id => params.append('ids', id));
            try {
                await apiDelete(endpoint + '?' + params.toString());
            } catch (e) {
                failed += batch.length;
                console.error('[删除操作] 批次删除失败:', e);
            }
            done += batch.length;
            updateDeleteProgress(done, total);
        }
        if (failed > 0) {
            toast(`删除完成：成功 ${total - failed} 条，失败 ${failed} 条`, 'warning');
        } else {
            toast(`成功删除 ${total} 条记录`, 'success');
        }
        state.selectedIds.clear();
        state.page = 1;
    } catch (e) {
        toast('删除失败: ' + e.message, 'error');
        return;
    }
    // 删除成功后强制刷新列表：先清空当前数据让页面立即响应，再重新拉取
    state.results = [];
    state.total = 0;
    state.totalPages = 0;
    state.expandedIds.clear();
    state.editingIds.clear();
    state.editData = {};
    renderResults();
    try {
        await loadResults();
        await updateStats(true);
    } catch (e) {
        // loadResults 内部已有 catch，这里的 catch 做兜底
        toast('列表刷新失败，请手动刷新', 'warning');
    }
    // 删除后重建合集（展示进度条）
    try {
        await rebuildGroups(state.currentConfigId);
    } catch (_) { /* 合集重建失败不阻断主流程 */ }
}

function confirmDelete() {
    if (state.selectedIds.size === 0) {
        toast('请先选择要删除的记录', 'warning');
        return;
    }
    deleteClearMode = false;
    showDeleteModal(
        `确定删除 ${state.selectedIds.size} 条记录？`,
        Array.from(state.selectedIds)
    );
}

function confirmClearAll() {
    if (!state.currentConfigId) {
        toast('请先选择一个扫描配置', 'warning');
        return;
    }
    deleteClearMode = true;
    showDeleteModal('确定清空当前扫描配置下的全部文件列表？\n（包括所有解析结果）', []);
}

async function deleteSingle(id) {
    deleteClearMode = false;
    showDeleteModal(`确定删除此文件？`, [id]);
}

async function refreshList() {
    if (!state.currentConfigId) {
        toast('请先选择一个扫描配置', 'warning');
        return;
    }
    const oldPage = state.page;
    await loadResults();
    state.page = oldPage;
    toast('列表已刷新', 'success');
}

// 数字输入框随内容自适应宽度
function autoSizeInput(el) {
    const text = (el.value || el.placeholder || '');
    // 每个字符约 9px，加左右内边距 16px，最小 46px
    const w = Math.max(46, text.length * 9 + 16);
    el.style.width = Math.min(w, 120) + 'px';
}

function toggleGroupMode() {
    // 弹出设置对话框
    const minEl = document.getElementById('minGroupCount');
    const maxEl = document.getElementById('maxGroupCount');
    minEl.value = state.minGroupCount || 0;
    maxEl.value = state.maxGroupCount != null ? state.maxGroupCount : '';
    document.getElementById('excludeGroupNames').value = state.excludeGroupNames || '';
    autoSizeInput(minEl);
    autoSizeInput(maxEl);
    openModal('groupModeModal');
}

async function confirmGroupMode() {
    const minVal = parseInt(document.getElementById('minGroupCount').value, 10);
    const maxRaw = document.getElementById('maxGroupCount').value;
    const maxVal = maxRaw === '' ? null : (parseInt(maxRaw, 10) || 0);
    const excludeRaw = document.getElementById('excludeGroupNames').value || '';
    state.minGroupCount = minVal || 0;
    state.maxGroupCount = maxVal;
    // 统一换行和逗号分隔，去掉空行
    state.excludeGroupNames = excludeRaw.split(/[\n,]+/).map(s => s.trim()).filter(Boolean).join(',');
    state.groupByFileName = !state.groupByFileName;
    const btn = document.getElementById('groupModeBtn');
    if (state.groupByFileName) {
        btn.textContent = '列表模式';
        btn.classList.add('btn-active');
    } else {
        btn.textContent = '合集模式';
        btn.classList.remove('btn-active');
    }
    state.page = 1;
    state.selectedIds.clear();
    state.expandedGroups.clear();
    closeModal('groupModeModal');

    // 切换"勾选重复"/"取消勾选"按钮的可见性
    const markDupBtn = document.getElementById('markDupBtn');
    const clearChecksBtn = document.getElementById('clearChecksBtn');
    if (markDupBtn) {
        markDupBtn.style.display = state.groupByFileName ? '' : 'none';
    }
    if (clearChecksBtn) {
        clearChecksBtn.style.display = state.groupByFileName ? '' : 'none';
    }

    // 进入合集模式时自动重建分组（按小说名聚合），确保从任意入口进入都能看到最新合集，
    // 避免 file_groups 为空导致合集页面空白。
    if (state.groupByFileName && state.currentConfigId) {
        await rebuildGroups(state.currentConfigId); // 内部会调用 loadResults()
        return;
    }

    loadResults();
}

// ===================== 勾选重复 =====================
async function markDuplicates() {
    if (!state.groupByFileName || !state.currentConfigId) {
        toast('请在合集模式下使用此功能', 'error');
        return;
    }
    if (state.groups.length === 0) {
        toast('当前页面没有合集数据', 'error');
        return;
    }

    const btn = document.getElementById('markDupBtn');
    const originalText = btn.textContent;
    btn.textContent = '计算中...';
    btn.disabled = true;

    try {
        const params = new URLSearchParams({
            config_id: state.currentConfigId,
            page: state.page,
            page_size: state.pageSize,
        });
        if (state.minGroupCount > 0) params.set('min_count', state.minGroupCount);
        if (state.maxGroupCount != null) params.set('max_count', state.maxGroupCount);
        if (state.excludeGroupNames) params.set('exclude_names', state.excludeGroupNames);

        const resp = await apiPost('/groups/select-duplicates?' + params.toString());
        const ids = resp.ids_to_check || [];
        const summary = resp.summary || {};

        if (ids.length === 0) {
            toast('未找到符合条件的重复文件（勾选重复）', 'info');
            return;
        }

        // 合并勾选（仅新增，不取消已有勾选）
        let addedCount = 0;
        for (const id of ids) {
            if (!state.selectedIds.has(id)) {
                state.selectedIds.add(id);
                addedCount++;
            }
        }

        // 刷新表格显示
        renderGroupedTableBody();
        updateStats(true);

        const sp = summary.groups_processed || 0;
        const sd = summary.subgroups_with_duplicates || 0;
        toast(
            `已处理 ${sp} 个合集，${sd} 个(作者+小说名)子组存在重复，` +
            `新增勾选 ${addedCount} 条（共应勾选 ${ids.length} 条）`,
            'success'
        );
    } catch (e) {
        toast('勾选重复失败: ' + (e.message || e), 'error');
    } finally {
        btn.textContent = originalText;
        btn.disabled = false;
    }
}

// ===================== 清除勾选 =====================
async function clearChecks() {
    if (!state.currentConfigId) {
        toast('请先选择配置', 'error');
        return;
    }

    const btn = document.getElementById('clearChecksBtn');
    const originalText = btn.textContent;
    btn.textContent = '取消中...';
    btn.disabled = true;

    try {
        const resp = await apiPost('/results/clear-checks?config_id=' + state.currentConfigId);
        const cleared = resp.cleared || 0;

        // 清除前端 selectedIds
        state.selectedIds.clear();

        // 刷新表格
        if (state.groupByFileName) {
            renderGroupedTableBody();
        } else {
            renderTableBody();
        }
        updateStats(true);

        toast(`已清除 ${cleared} 条勾选`, 'success');
    } catch (e) {
        toast('清除勾选失败: ' + (e.message || e), 'error');
    } finally {
        btn.textContent = originalText;
        btn.disabled = false;
    }
}

// ===================== 勾选状态筛选 =====================
function setCheckedFilter(filter) {
    if (state.checkedFilter === filter) return;
    state.checkedFilter = filter;
    state.page = 1;  // 重置到第一页
    // 更新按钮 active 样式
    document.querySelectorAll('.checked-filter-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.filter === filter);
    });
    loadResults();
}

// ===================== 侧栏折叠 =====================
function toggleSidebar() {
    const sidebar = document.getElementById('sidebar');
    const isCollapsed = sidebar.classList.toggle('collapsed');
    const btn = sidebar.querySelector('.sidebar-toggle');
    btn.textContent = isCollapsed ? '▶' : '◀';
    btn.title = isCollapsed ? '展开侧栏' : '折叠侧栏';
    localStorage.setItem('sidebarCollapsed', isCollapsed);
}

// 页面加载时恢复折叠状态
document.addEventListener('DOMContentLoaded', () => {
    if (localStorage.getItem('sidebarCollapsed') === 'true') {
        const sidebar = document.getElementById('sidebar');
        if (sidebar) {
            sidebar.classList.add('collapsed');
            const btn = sidebar.querySelector('.sidebar-toggle');
            if (btn) {
                btn.textContent = '▶';
                btn.title = '展开侧栏';
            }
        }
    }
    applyFontSize();
});

// ===================== 界面字体大小 =====================
function applyFontSize() {
    const size = localStorage.getItem('fontSize') || 'standard';
    document.body.setAttribute('data-font', size);
    const sel = document.getElementById('fontSizeSelect');
    if (sel) sel.value = size;
    const hint = document.getElementById('fontSizeHint');
    if (hint) {
        hint.textContent = size === 'small' ? '当前：小' : (size === 'large' ? '当前：大' : '当前：标准');
    }
}

function onFontSizeChange() {
    const sel = document.getElementById('fontSizeSelect');
    if (!sel) return;
    localStorage.setItem('fontSize', sel.value);
    applyFontSize();
}

// ===================== 回到顶部/底部 =====================
function scrollToTop() {
    window.scrollTo({ top: 0, behavior: 'smooth' });
}

function scrollToBottom() {
    window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'smooth' });
}

function updateBackNav() {
    const nav = document.getElementById('backNav');
    if (!nav) return;
    const top = window.scrollY;
    const viewport = window.innerHeight;
    const scrollHeight = document.documentElement.scrollHeight;
    const showUp = top > 300;                                  // 「回到顶部」：离开顶部时可用
    const showDown = (top + viewport) < (scrollHeight - 300);  // 「回到底部」：未接近底部时可用
    const upBtn = document.getElementById('backToTopBtn');
    const downBtn = document.getElementById('backToBottomBtn');
    if (upBtn) upBtn.style.display = showUp ? '' : 'none';
    if (downBtn) downBtn.style.display = showDown ? '' : 'none';
    nav.classList.toggle('show', showUp || showDown);
}

window.addEventListener('scroll', updateBackNav, { passive: true });
window.addEventListener('resize', updateBackNav, { passive: true });

// ===================== 搜索（带防抖） =====================
function debounce(fn, delay) {
    let timer;
    return function (...args) {
        clearTimeout(timer);
        timer = setTimeout(() => fn.apply(this, args), delay);
    };
}

const debouncedSearch = debounce(function () {
    state.searchText = document.getElementById('searchInput').value.trim();
    state.sortClicks = {};
    state.page = 1;
    loadResults();
}, 400);

// ===================== 小说名筛选 =====================

function toggleFilterDropdown() {
    state.showFilterDropdown = !state.showFilterDropdown;
    const dropdown = document.getElementById('filterDropdown');
    if (dropdown) {
        dropdown.style.display = state.showFilterDropdown ? 'flex' : 'none';
    }
    if (state.showFilterDropdown) {
        // 同步当前选中的小说名到待选列表
        state.selectedNovelNames = new Set(state.activeNovelNames);
        state.filterPage = 1;
        state.filterTotalPages = 1;
        state.filterTotalItems = 0;
        state.filterLoading = false;
        loadNovelNames();
    }
}

async function loadNovelNames() {
    if (!state.currentConfigId) return;
    if (state.filterLoading) return;
    state.filterLoading = true;
    try {
        const params = new URLSearchParams({
            config_id: state.currentConfigId,
            page: state.filterPage,
            page_size: state.filterPageSize,
        });
        if (state.filterSearchText) {
            params.set('search', state.filterSearchText);
        }
        const resp = await apiGet('/novel-names?' + params.toString());
        if (state.filterPage === 1) {
            state.filterNovelNames = resp.items || [];
        } else {
            // 追加模式（加载更多）
            state.filterNovelNames = state.filterNovelNames.concat(resp.items || []);
        }
        state.filterTotalPages = resp.total_pages || 1;
        state.filterTotalItems = resp.total || 0;
        renderFilterList(state.filterPage === 1);
    } catch (e) {
        toast('加载小说名列表失败: ' + e.message, 'error');
    } finally {
        state.filterLoading = false;
    }
}

function renderFilterList(fullRender) {
    const list = document.getElementById('filterList');
    if (!list) return;

    // 首次渲染或全量刷新时重建DOM
    if (fullRender) {
        if (state.filterNovelNames.length === 0) {
            list.innerHTML = '<div class="filter-empty">暂无小说名数据</div>';
            updateFilterCountInfo();
            return;
        }
        list.innerHTML = state.filterNovelNames.map(item => {
            const isBlank = item.novel_name === '__empty__';
            const dataValue = isBlank ? '__empty__' : item.novel_name;
            const displayName = isBlank ? '(空白)' : item.novel_name;
            const checked = state.selectedNovelNames.has(dataValue);
            const escapedDisplay = escapeHtml(displayName);
            return `<div class="filter-item" data-novel-name="${dataValue}">
                <input type="checkbox" ${checked ? 'checked' : ''}>
                <span class="filter-item-name">${escapedDisplay}</span>
                <span class="filter-item-count">${item.count}</span>
            </div>`;
        }).join('');

        // 添加"加载更多"按钮（有更多数据时）
        if (state.filterPage < state.filterTotalPages) {
            const loadMoreBtn = document.createElement('div');
            loadMoreBtn.className = 'filter-load-more';
            loadMoreBtn.dataset.action = 'loadMoreFilter';
            loadMoreBtn.textContent = '加载更多...';
            list.appendChild(loadMoreBtn);
        }

        // 绑定事件委托（只绑定一次）
        if (!state.filterListRendered) {
            state.filterListRendered = true;
            list.addEventListener('click', function (e) {
                // 加载更多按钮
                const loadMore = e.target.closest('[data-action="loadMoreFilter"]');
                if (loadMore) {
                    state.filterPage++;
                    loadNovelNames();
                    return;
                }
                // 小说名勾选
                const filterItem = e.target.closest('.filter-item');
                if (filterItem) {
                    const novelName = filterItem.dataset.novelName;
                    if (!novelName) return;
                    if (state.selectedNovelNames.has(novelName)) {
                        state.selectedNovelNames.delete(novelName);
                    } else {
                        state.selectedNovelNames.add(novelName);
                    }
                    // 直接同步复选框状态
                    const checkbox = filterItem.querySelector('input[type="checkbox"]');
                    if (checkbox) {
                        checkbox.checked = state.selectedNovelNames.has(novelName);
                    }
                    updateFilterCountInfo();
                }
            });
        }
    } else {
        // 追加渲染：只追加新增的 items
        const existingItems = list.querySelectorAll('.filter-item');
        const existingCount = existingItems.length;
        const newItemsHtml = state.filterNovelNames.slice(existingCount).map(item => {
            const isBlank = item.novel_name === '__empty__';
            const dataValue = isBlank ? '__empty__' : item.novel_name;
            const displayName = isBlank ? '(空白)' : item.novel_name;
            const checked = state.selectedNovelNames.has(dataValue);
            const escapedDisplay = escapeHtml(displayName);
            return `<div class="filter-item" data-novel-name="${dataValue}">
                <input type="checkbox" ${checked ? 'checked' : ''}>
                <span class="filter-item-name">${escapedDisplay}</span>
                <span class="filter-item-count">${item.count}</span>
            </div>`;
        }).join('');

        // 移除旧的"加载更多"按钮
        const oldLoadMore = list.querySelector('[data-action="loadMoreFilter"]');
        if (oldLoadMore) oldLoadMore.remove();

        // 追加新item
        if (newItemsHtml) {
            list.insertAdjacentHTML('beforeend', newItemsHtml);
        }

        // 添加"加载更多"按钮（有更多数据时）
        if (state.filterPage < state.filterTotalPages) {
            const loadMoreBtn = document.createElement('div');
            loadMoreBtn.className = 'filter-load-more';
            loadMoreBtn.dataset.action = 'loadMoreFilter';
            loadMoreBtn.textContent = '加载更多...';
            list.appendChild(loadMoreBtn);
        }
    }

    // 更新数量和页脚信息
    updateFilterCountInfo();
    updateFilterFooterInfo();
}

function updateFilterFooterInfo() {
    const footer = document.querySelector('.filter-footer .filter-info-text');
    if (!footer) {
        const countEl = document.getElementById('filterCountInfo');
        if (countEl) {
            const shown = state.filterNovelNames.length;
            const total = state.filterTotalItems;
            if (total > state.filterPageSize) {
                countEl.textContent = `已选 ${state.selectedNovelNames.size} 个（显示 ${shown}/${total}）`;
            } else {
                countEl.textContent = `已选 ${state.selectedNovelNames.size} 个`;
            }
        }
        return;
    }
    footer.textContent = state.filterTotalItems > 0
        ? `显示 ${state.filterNovelNames.length}/${state.filterTotalItems}`
        : '';
}

function toggleFilterItemFromElement(el) {
    // 保留此函数的兼容性，新代码走事件委托
    const novelName = el.getAttribute('data-novel-name');
    if (!novelName) return;
    if (state.selectedNovelNames.has(novelName)) {
        state.selectedNovelNames.delete(novelName);
    } else {
        state.selectedNovelNames.add(novelName);
    }
    const checkbox = el.querySelector('input[type="checkbox"]');
    if (checkbox) {
        checkbox.checked = state.selectedNovelNames.has(novelName);
    }
    updateFilterCountInfo();
}

function selectAllFilteredNames() {
    // 选中所有已加载的
    state.filterNovelNames.forEach(item => {
        state.selectedNovelNames.add(item.novel_name);
    });
    // 只同步所有复选框状态，不重渲染整个列表
    const list = document.getElementById('filterList');
    if (list) {
        list.querySelectorAll('.filter-item input[type="checkbox"]').forEach(cb => {
            cb.checked = true;
        });
    }
    updateFilterCountInfo();
    updateFilterFooterInfo();
}

function clearAllFilteredNames() {
    state.selectedNovelNames.clear();
    // 只同步所有复选框状态，不重渲染整个列表
    const list = document.getElementById('filterList');
    if (list) {
        list.querySelectorAll('.filter-item input[type="checkbox"]').forEach(cb => {
            cb.checked = false;
        });
    }
    updateFilterCountInfo();
    updateFilterFooterInfo();
}

function applyNovelNameFilter() {
    state.activeNovelNames = new Set(state.selectedNovelNames);
    state.showFilterDropdown = false;
    const dropdown = document.getElementById('filterDropdown');
    if (dropdown) dropdown.style.display = 'none';
    state.page = 1;
    updateFilterBadge();
    loadResults();
}

function updateFilterBadge() {
    const badge = document.getElementById('filterBadge');
    if (!badge) return;
    const count = state.activeNovelNames.size;
    if (count > 0) {
        badge.style.display = 'inline-flex';
        badge.textContent = count;
    } else {
        badge.style.display = 'none';
    }
}

function updateFilterCountInfo() {
    const el = document.getElementById('filterCountInfo');
    if (el) {
        el.textContent = `已选 ${state.selectedNovelNames.size} 个`;
    }
}

const debouncedFilterSearch = debounce(function () {
    state.filterSearchText = document.getElementById('filterSearchInput').value.trim();
    state.filterPage = 1;
    state.filterNovelNames = [];
    loadNovelNames();
}, 300);

// 点击页面空白处关闭筛选下拉框
document.addEventListener('click', function (e) {
    const filterWrapper = document.querySelector('.filter-wrapper');
    const dropdown = document.getElementById('filterDropdown');
    if (filterWrapper && dropdown && state.showFilterDropdown) {
        if (!filterWrapper.contains(e.target)) {
            state.showFilterDropdown = false;
            dropdown.style.display = 'none';
        }
    }
});

// ===================== 一键清理流程 =====================
let pipelinePollTimer = null;
let pipelineLogTimer = null;
let pipelineAwaitingHandled = false;

async function loadPipelinePage() {
    stopPipelinePoll();
    try {
        const configs = await apiGet('/configs');
        const sel = document.getElementById('pipelineConfig');
        if (sel) {
            sel.innerHTML = '<option value="">-- 选择扫描配置 --</option>'
                + configs.map(c => `<option value=\"${c.id}\">[${c.id}] ${escapeHtml(c.name || c.folder_path)}</option>`).join('');
        }
    } catch (e) {
        toast('加载配置失败: ' + (e.message || e), 'error');
    }
    const st = await fetchPipelineStatus();
    renderPipeline(st);
    if (st.status === 'running' || st.status === 'awaiting_confirm') startPipelinePoll();
}

async function fetchPipelineStatus() {
    try { return await apiGet('/pipeline/status'); }
    catch (e) { return { status: 'idle' }; }
}

function startPipelinePoll() {
    stopPipelinePoll();
    pipelinePollTimer = setInterval(async () => {
        const st = await fetchPipelineStatus();
        renderPipeline(st);
        if (st.status !== 'running' && st.status !== 'awaiting_confirm') stopPipelinePoll();
    }, 1000);
}
function stopPipelinePoll() {
    if (pipelinePollTimer) { clearInterval(pipelinePollTimer); pipelinePollTimer = null; }
}

async function startPipeline() {
    const sel = document.getElementById('pipelineConfig');
    const configId = sel ? sel.value : '';
    if (!configId) { toast('请选择扫描配置', 'warning'); return; }
    const mode = document.querySelector('input[name=\"pipelineDeleteMode\"]:checked')?.value || 'db';
    try {
        await apiPost('/pipeline/start', { config_id: parseInt(configId), delete_mode: mode });
        toast('已启动一键清理', 'success');
        const st = await fetchPipelineStatus();
        renderPipeline(st);
        startPipelinePoll();
    } catch (e) {
        toast('启动失败: ' + (e.message || e), 'error');
    }
}

async function cancelPipeline() {
    if (!confirm('确定取消当前一键清理流程？已完成节点将保留，但后续步骤（含删除）不会执行。')) return;
    try {
        await apiPost('/pipeline/cancel', {});
        toast('已发送取消信号', 'info');
    } catch (e) {
        toast('取消失败: ' + (e.message || e), 'error');
    }
}

async function confirmPipelineDelete() {
    closeModal('pipelineConfirmModal');
    try {
        await apiPost('/pipeline/confirm', {});
        toast('已确认，开始删除...', 'info');
        startPipelinePoll();
        renderPipeline(await fetchPipelineStatus());
    } catch (e) {
        toast('确认失败: ' + (e.message || e), 'error');
    }
}

function cancelPipelineDelete() {
    closeModal('pipelineConfirmModal');
    cancelPipeline();
}

function statusLabel(s) {
    return ({ idle: '空闲', running: '进行中', awaiting_confirm: '待确认', done: '已完成', cancelled: '已取消', error: '出错' })[s] || s;
}

function formatDuration(sec) {
    sec = Math.max(0, Math.floor(sec));
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    if (h > 0) return `${h}时${m}分${s}秒`;
    if (m > 0) return `${m}分${s}秒`;
    return `${s}秒`;
}

function renderPipeline(st) {
    const container = document.getElementById('pipelineNodes');
    if (!container) return;
    if (st.status === 'idle' || !st.status) {
        container.innerHTML = '<div class=\"empty-state\" style=\"padding:16px;color:var(--text-secondary)\">当前没有进行中的流程。</div>';
        const overall = document.getElementById('pipelineOverall');
        if (overall) overall.style.display = 'none';
        const actions = document.getElementById('pipelineActions');
        if (actions) actions.style.display = 'none';
        return;
    }
    const overall = document.getElementById('pipelineOverall');
    if (overall) overall.style.display = 'flex';
    const start = st.started_at ? new Date(st.started_at) : null;
    const elapsed = start ? formatDuration((Date.now() - start.getTime()) / 1000) : '-';
    const badge = document.getElementById('pipelineStatusBadge');
    if (badge) { badge.textContent = statusLabel(st.status); badge.className = 'pipeline-badge badge-' + st.status; }
    const stEl = document.getElementById('pipelineStartTime');
    if (stEl) stEl.textContent = start ? start.toLocaleString() : '-';
    const elEl = document.getElementById('pipelineElapsed');
    if (elEl) elEl.textContent = elapsed;

    container.innerHTML = (st.nodes || []).map(n => {
        const pct = n.total > 0 ? Math.round(n.processed / n.total * 100) : 0;
        const isDone = n.status === 'done';
        const indeterminate = (n.status === 'running' && (n.key === 'scan' || n.key === 'group' || n.key === 'mark'));
        const bar = indeterminate
            ? '<div class=\"pnode-bar\"><div class=\"pnode-bar-ind\"></div></div>'
            : `<div class=\"pnode-bar\"><div class=\"pnode-bar-fill${isDone ? ' done' : ''}\" style=\"width:${isDone ? 100 : pct}%\"></div></div>`;
        const detail = n.total > 0 ? `${n.processed} / ${n.total}（${pct}%）` : (n.message || '');
        return `<div class=\"pnode\">
            <div class=\"pnode-head\"><span class=\"pname\">${n.name}</span>
                <span class=\"pipeline-badge badge-${n.status}\">${statusLabel(n.status)}</span></div>
            ${bar}
            <div class=\"pnode-detail\">${escapeHtml(detail)}</div>
        </div>`;
    }).join('');

    const actions = document.getElementById('pipelineActions');
    if (actions) actions.style.display = (st.status === 'running' || st.status === 'awaiting_confirm') ? 'block' : 'none';

    if (st.status !== 'awaiting_confirm') pipelineAwaitingHandled = false;
    if (st.status === 'awaiting_confirm' && !pipelineAwaitingHandled) {
        showPipelineConfirm(st);
        pipelineAwaitingHandled = true;
    }
}

function showPipelineConfirm(st) {
    const modal = document.getElementById('pipelineConfirmModal');
    if (!modal) return;
    const isFile = st.delete_mode === 'file';
    const label = isFile ? `将被删除的 ${st.deletion_count} 个文件清单` : `将被删除的 ${st.deletion_count} 个数据记录`;
    const title = document.getElementById('pipelineConfirmTitle');
    if (title) title.textContent = label;
    const note = document.getElementById('pipelineConfirmNote');
    if (note) note.textContent = st.preview_truncated ? '（仅显示前 500 条，实际数量见上方标题）' : '';
    const sample = st.preview_sample || [];
    const list = document.getElementById('pipelineConfirmList');
    if (list) {
        list.innerHTML = sample.map(p =>
            `<div class=\"pconfirm-item\"><span class=\"pconfirm-id\">#${p.id}</span> <span class=\"pconfirm-name\">${escapeHtml(p.file_name)}</span>`
            + (isFile ? `<span class=\"pconfirm-path\">${escapeHtml(p.file_path)}</span>` : '') + `</div>`
        ).join('') || '<div class=\"empty-state\">清单为空</div>';
    }
    modal.style.display = 'flex';
}

// ===================== 调试日志（操作日志 + 调试日志，一键复制） =====================
let debugLogMode = 'op';   // 'op' = 操作日志, 'pipe' = 调试日志
let debugLogTimer = null;
let debugLogLast = '';       // 缓存最近一次文本，避免重复渲染

function switchDebugLog(mode) {
    debugLogMode = mode;
    document.getElementById('debugLogOpBtn').classList.toggle('btn-primary', mode === 'op');
    document.getElementById('debugLogPipeBtn').classList.toggle('btn-primary', mode === 'pipe');
    debugLogLast = '';  // 切换时强制刷新
    refreshDebugLog();
}

// 读取当前模式的日志文本（纯文本，用于展示与复制）
async function fetchDebugLogText() {
    const url = debugLogMode === 'op' ? '/api/operation-logs' : '/api/pipeline-logs';
    const resp = await apiGet(url);
    const logs = resp.logs || [];
    if (debugLogMode === 'op') {
        // 操作日志是完整记录（含换行），直接拼接
        return logs.join('\n\n');
    }
    // 调试日志为 [{time, level, msg}]，还原为单行
    return logs.map(l => `[${l.time}] [${l.level}] ${l.msg}`).join('\n');
}

async function refreshDebugLog() {
    const box = document.getElementById('debugLogBox');
    if (!box) return;
    try {
        const text = await fetchDebugLogText();
        if (text !== debugLogLast) {
            debugLogLast = text;
            box.textContent = text || (debugLogMode === 'op' ? '暂无操作日志' : '暂无调试日志');
            box.scrollTop = box.scrollHeight;
        }
    } catch (e) { /* 忽略轮询错误 */ }
}

// 一键复制当前日志到剪贴板
async function copyDebugLog() {
    const box = document.getElementById('debugLogBox');
    if (!box) return;
    let text = box.textContent || "";
    if (!text.trim()) {
        try { text = await fetchDebugLogText(); } catch (e) { text = ""; }
    }
    if (!text.trim()) { alert('当前没有可复制的日志'); return; }
    try {
        await navigator.clipboard.writeText(text);
    } catch (e) {
        const ta = document.createElement("textarea");
        ta.value = text; document.body.appendChild(ta); ta.select();
        try { document.execCommand("copy"); } catch (_) {}
        document.body.removeChild(ta);
    }
    const btn = document.getElementById('debugLogCopyBtn');
    const old = btn.textContent;
    btn.textContent = '已复制 \u2713';
    setTimeout(() => { btn.textContent = old; }, 1500);
}

// 进入一键清理页时自动开始轮询，离开时停止
function startDebugLogPoll() {
    stopDebugLogPoll();
    refreshDebugLog();
    debugLogTimer = setInterval(refreshDebugLog, 2000);
}
function stopDebugLogPoll() {
    if (debugLogTimer) { clearInterval(debugLogTimer); debugLogTimer = null; }
}
// ===================== 独立日志页面（操作日志 + 调试日志） =====================
let logViewMode = 'op';   // 'op' = 操作日志, 'debug' = 调试日志(app.log)
let logPageTimer = null;
let logPageLast = '';       // 缓存最近一次文本，避免重复渲染

function switchLogView(mode) {
    logViewMode = mode;
    const opBtn = document.getElementById('logOpBtn');
    const dbgBtn = document.getElementById('logDebugBtn');
    if (opBtn) opBtn.classList.toggle('btn-primary', mode === 'op');
    if (dbgBtn) dbgBtn.classList.toggle('btn-primary', mode === 'debug');
    logPageLast = '';  // 切换时强制刷新
    refreshLogPage();
}

// 读取当前模式的日志文本（纯文本，用于展示与复制）
async function fetchLogPageText() {
    const url = logViewMode === 'op' ? '/api/operation-logs' : '/api/app-logs';
    const resp = await apiGet(url);
    const logs = resp.logs || [];
    if (logViewMode === 'op') {
        // 操作日志是完整记录（含换行），直接拼接
        return logs.join('\n\n');
    }
    // 调试日志为 app.log 原始行，直接拼接
    return logs.join('\n');
}

async function refreshLogPage() {
    const box = document.getElementById('logPageBox');
    if (!box) return;
    try {
        const text = await fetchLogPageText();
        if (text !== logPageLast) {
            logPageLast = text;
            box.textContent = text || (logViewMode === 'op' ? '暂无操作日志' : '暂无调试日志');
            box.scrollTop = box.scrollHeight;
        }
    } catch (e) { /* 忽略轮询错误 */ }
}

// 一键复制当前日志到剪贴板
async function copyLogPage() {
    const box = document.getElementById('logPageBox');
    if (!box) return;
    let text = box.textContent || '';
    if (!text.trim()) {
        try { text = await fetchLogPageText(); } catch (e) { text = ''; }
    }
    if (!text.trim()) { alert('当前没有可复制的日志'); return; }
    try {
        await navigator.clipboard.writeText(text);
    } catch (e) {
        const ta = document.createElement('textarea');
        ta.value = text; document.body.appendChild(ta); ta.select();
        try { document.execCommand('copy'); } catch (_) {}
        document.body.removeChild(ta);
    }
    const btn = document.getElementById('logCopyBtn');
    const old = btn.textContent;
    btn.textContent = '已复制 \u2713';
    setTimeout(() => { btn.textContent = old; }, 1500);
}

// 进入日志页时自动开始轮询，离开时停止
function startLogPagePoll() {
    stopLogPagePoll();
    refreshLogPage();
    logPageTimer = setInterval(refreshLogPage, 3000);
}
function stopLogPagePoll() {
    if (logPageTimer) { clearInterval(logPageTimer); logPageTimer = null; }
}

// ===================== 勾选重复规则配置（内置 + 用户自定义 CRUD） =====================
async function loadDupRuleConfigs() {
    try {
        const rules = await apiGet('/dup-rule-configs');
        renderDupRuleConfigs(rules || []);
    } catch (e) {
        toast('加载勾选重复规则失败: ' + (e.message || e), 'error');
    }
}

function escAttr(s) { return ('' + s).replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

function renderDupRuleConfigs(rules) {
    const container = document.getElementById('dupRuleConfigs');
    if (!container) return;
    // 分离内置和用户规则
    const builtins = rules.filter(r => r.is_builtin);
    const userRules = rules.filter(r => !r.is_builtin);
    let html = '';
    // 内置规则区块
    if (builtins.length) {
        html += '<div style="font-size:11px;color:var(--text-secondary);margin:4px 0 2px;font-weight:500">内置规则（不可删除）</div>';
        builtins.forEach(r => {
            html += renderDupRuleRow(r);
        });
    }
    // 用户规则区块
    if (userRules.length) {
        html += '<div style="font-size:11px;color:var(--text-secondary);margin:10px 0 2px;font-weight:500">自定义规则</div>';
        userRules.forEach(r => {
            html += renderDupRuleRow(r);
        });
    }
    if (!rules.length) {
        html = '<div style="font-size:12px;color:var(--text-secondary);padding:12px;text-align:center">暂无规则，点击下方「添加自定义规则」创建</div>';
    }
    container.innerHTML = html;
}

function renderDupRuleRow(r) {
    const checked = r.enabled ? 'checked' : '';
    const badge = r.is_builtin
        ? '<span style="font-size:10px;padding:1px 5px;border-radius:3px;background:var(--accent);color:#fff;margin-left:6px;white-space:nowrap">内置</span>'
        : '<span style="font-size:10px;padding:1px 5px;border-radius:3px;background:var(--warning);color:#333;margin-left:6px;white-space:nowrap">自定义</span>';
    const actionLabel = r.action === 'protect' ? '🛡️' : '✓';
    const actionText = r.action === 'protect' ? '保护' : '勾选';
    const deleteBtn = r.is_builtin
        ? ''
        : `<button onclick="deleteUserRule(${r.id})" style="border:none;background:none;color:var(--danger,#e74c3c);cursor:pointer;font-size:14px;padding:2px 4px" title="删除该自定义规则">✕</button>`;
    const editBtn = r.is_builtin
        ? ''
        : `<button onclick="editUserRule(${r.id})" style="border:none;background:none;color:var(--accent);cursor:pointer;font-size:12px;padding:2px 4px" title="编辑该自定义规则">✎</button>`;
    const descHtml = r.is_builtin
        ? escHtml(r.description)
        : `${actionText} - ${escHtml(r.description || '')}`;
    return `<div style="display:flex;align-items:center;gap:8px;padding:6px 8px;border-radius:6px;background:var(--bg-secondary)">
        <input type="checkbox" class="dup-rule-toggle" data-rule-id="${r.id}" ${checked} style="width:18px;height:18px;cursor:pointer">
        <div style="flex:1;min-width:0">
            <div style="font-size:13px;font-weight:500">${escHtml(r.rule_name)}${badge}</div>
            <div style="font-size:11px;color:var(--text-secondary);margin-top:2px">${descHtml}</div>
        </div>
        ${editBtn}${deleteBtn}
    </div>`;
}

async function saveDupRuleConfigs() {
    const toggles = document.querySelectorAll('.dup-rule-toggle');
    const payload = [];
    toggles.forEach(cb => {
        payload.push({ id: parseInt(cb.dataset.ruleId), enabled: cb.checked });
    });
    try {
        await apiPut('/dup-rule-configs', payload);
        toast('勾选重复规则已保存', 'success');
        loadDupRuleConfigs(); // 刷新显示
    } catch (e) {
        toast('保存失败: ' + (e.message || e), 'error');
    }
}

// ===================== 用户自定义规则 CRUD =====================

// 当前编辑条件列表
let _userRuleConditions = [];

function showAddUserRuleDialog() {
    document.getElementById('userRuleDialogTitle').textContent = '添加自定义去重规则';
    document.getElementById('userRuleEditId').value = '';
    document.getElementById('userRuleName').value = '';
    document.getElementById('userRuleAction').value = 'check';
    document.getElementById('userRuleDesc').value = '';
    _userRuleConditions = [{ field: 'file_name', op: 'contains', value: '' }];
    renderUserRuleConditions();
    document.getElementById('userRuleDialog').style.display = 'flex';
}

function closeUserRuleDialog() {
    document.getElementById('userRuleDialog').style.display = 'none';
}

function addUserRuleConditionRow() {
    _userRuleConditions.push({ field: 'file_name', op: 'contains', value: '' });
    renderUserRuleConditions();
}

function removeUserRuleConditionRow(index) {
    _userRuleConditions.splice(index, 1);
    renderUserRuleConditions();
}

function onUserRuleFieldChange(index) {
    const fieldSelect = document.getElementById('condField_' + index);
    const opSelect = document.getElementById('condOp_' + index);
    if (!fieldSelect || !opSelect) return;
    const field = fieldSelect.value;
    const isNumeric = field === 'file_size';
    const isText = !isNumeric && field !== 'created_date';
    // 更新运算符选项
    let ops;
    if (isNumeric) {
        ops = [
            { v: 'eq', l: '等于' },
            { v: 'neq', l: '不等于' },
            { v: 'gt', l: '大于' },
            { v: 'gte', l: '大于等于' },
            { v: 'lt', l: '小于' },
            { v: 'lte', l: '小于等于' },
            { v: 'between', l: '在区间内' },
        ];
    } else if (field === 'created_date') {
        ops = [
            { v: 'before', l: '早于' },
            { v: 'after', l: '晚于' },
            { v: 'within_days', l: 'X天内' },
        ];
    } else {
        ops = [
            { v: 'eq', l: '等于' },
            { v: 'neq', l: '不等于' },
            { v: 'contains', l: '包含' },
            { v: 'not_contains', l: '不包含' },
            { v: 'starts_with', l: '开头是' },
            { v: 'ends_with', l: '结尾是' },
            { v: 'regex', l: '匹配正则' },
        ];
    }
    opSelect.innerHTML = ops.map(o => `<option value="${o.v}">${o.l}</option>`).join('');
    // 如果当前值不在新选项里，重置
    const currentVal = _userRuleConditions[index]?.op || 'contains';
    if (ops.find(o => o.v === currentVal)) {
        opSelect.value = currentVal;
    }
    _userRuleConditions[index].op = opSelect.value;
    // 更新值输入框类型
    const valueInput = document.getElementById('condValue_' + index);
    if (valueInput) {
        valueInput.type = isNumeric ? 'number' : 'text';
        valueInput.placeholder = isNumeric ? '字节数，如 1048576' : '值';
    }
}

function renderUserRuleConditions() {
    const container = document.getElementById('userRuleConditions');
    if (!container) return;
    container.innerHTML = _userRuleConditions.map((c, i) => {
        const fields = [
            { v: 'file_name', l: '文件名' },
            { v: 'novel_name', l: '小说名' },
            { v: 'author', l: '作者' },
            { v: 'progress', l: '进度' },
            { v: 'source', l: '来源' },
            { v: 'file_size', l: '文件大小（字节）' },
            { v: 'created_date', l: '创建日期' },
        ];
        const fieldOptions = fields.map(f =>
            `<option value="${f.v}" ${f.v === c.field ? 'selected' : ''}>${f.l}</option>`
        ).join('');
        const isNumeric = c.field === 'file_size';
        const isDate = c.field === 'created_date';
        let ops;
        if (isNumeric) {
            ops = [
                ['eq', '等于'], ['neq', '不等于'], ['gt', '大于'],
                ['gte', '大于等于'], ['lt', '小于'], ['lte', '小于等于'],
                ['between', '在区间内'],
            ];
        } else if (isDate) {
            ops = [['before', '早于'], ['after', '晚于'], ['within_days', 'X天内']];
        } else {
            ops = [
                ['eq', '等于'], ['neq', '不等于'], ['contains', '包含'],
                ['not_contains', '不包含'], ['starts_with', '开头是'],
                ['ends_with', '结尾是'], ['regex', '匹配正则'],
            ];
        }
        const opOptions = ops.map(o =>
            `<option value="${o[0]}" ${o[0] === c.op ? 'selected' : ''}>${o[1]}</option>`
        ).join('');
        const inputType = isNumeric ? 'number' : 'text';
        const placeholder = isNumeric ? '字节数' : isDate ? '2024-01-01' : '值';
        return `<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap">
            <span style="font-size:11px;color:var(--text-secondary);font-weight:500">如果</span>
            <select id="condField_${i}" onchange="onUserRuleFieldChange(${i})" style="padding:4px 6px;border:1px solid var(--border);border-radius:4px;font-size:12px;background:var(--bg-primary);color:var(--text-primary);flex:1">${fieldOptions}</select>
            <select id="condOp_${i}" onchange="_userRuleConditions[${i}].op=this.value" style="padding:4px 6px;border:1px solid var(--border);border-radius:4px;font-size:12px;background:var(--bg-primary);color:var(--text-primary);flex:0 0 auto">${opOptions}</select>
            <input id="condValue_${i}" type="${inputType}" placeholder="${placeholder}" value="${escAttr(c.value || '')}"
                   oninput="_userRuleConditions[${i}].value=this.value"
                   style="padding:4px 8px;border:1px solid var(--border);border-radius:4px;font-size:12px;background:var(--bg-primary);color:var(--text-primary);flex:1;min-width:80px">
            <button onclick="removeUserRuleConditionRow(${i})" style="border:none;background:none;color:var(--danger,#e74c3c);cursor:pointer;font-size:14px;padding:2px">✕</button>
        </div>`;
    }).join('');
}

async function saveUserRule() {
    const editId = document.getElementById('userRuleEditId').value;
    const name = document.getElementById('userRuleName').value.trim();
    const action = document.getElementById('userRuleAction').value;
    const desc = document.getElementById('userRuleDesc').value.trim();

    if (!name) { toast('请输入规则名称', 'error'); return; }

    // 收集条件
    const conditions = _userRuleConditions.filter(c => c.field && c.value !== undefined && c.value !== '');
    if (!conditions.length) { toast('请至少添加一个有效的条件', 'error'); return; }

    try {
        if (editId) {
            // 更新
            await apiPut('/dup-rule-configs', [{
                id: parseInt(editId),
                rule_name: name,
                description: desc,
                action: action,
                conditions: conditions,
            }]);
            toast('自定义规则已更新', 'success');
        } else {
            // 新建
            await apiPost('/dup-rule-configs', {
                rule_name: name,
                description: desc,
                action: action,
                conditions: conditions,
                enabled: true,
            });
            toast('自定义规则已创建', 'success');
        }
        closeUserRuleDialog();
        loadDupRuleConfigs();
    } catch (e) {
        toast('保存自定义规则失败: ' + (e.message || e), 'error');
    }
}

async function deleteUserRule(id) {
    if (!confirm('确认删除这条自定义规则？')) return;
    try {
        await apiDelete('/dup-rule-configs/' + id);
        toast('自定义规则已删除', 'success');
        loadDupRuleConfigs();
    } catch (e) {
        toast('删除失败: ' + (e.message || e), 'error');
    }
}

async function editUserRule(id) {
    try {
        const rules = await apiGet('/dup-rule-configs');
        const rule = rules.find(r => r.id === id);
        if (!rule) { toast('规则不存在', 'error'); return; }
        document.getElementById('userRuleDialogTitle').textContent = '编辑自定义去重规则';
        document.getElementById('userRuleEditId').value = id;
        document.getElementById('userRuleName').value = rule.rule_name || '';
        document.getElementById('userRuleAction').value = rule.action || 'check';
        document.getElementById('userRuleDesc').value = rule.description || '';
        _userRuleConditions = (rule.conditions && rule.conditions.length)
            ? JSON.parse(JSON.stringify(rule.conditions))
            : [{ field: 'file_name', op: 'contains', value: '' }];
        renderUserRuleConditions();
        document.getElementById('userRuleDialog').style.display = 'flex';
    } catch (e) {
        toast('加载规则失败: ' + (e.message || e), 'error');
    }
}

// ===================== 关键词替换设置 =====================
async function loadKeywordRules() {
    try {
        const resp = await apiGet('/keyword-replaces');
        renderKeywordRules(resp.rules || []);
    } catch (e) {
        toast('加载关键词规则失败: ' + (e.message || e), 'error');
    }
}

function renderKeywordRules(rules) {
    const scanList = document.getElementById('scanRuleList');
    const parseList = document.getElementById('parseRuleList');
    if (!scanList || !parseList) return;
    const scanRules = rules.filter(r => r.scope === 'scan');
    const parseRules = rules.filter(r => r.scope === 'parse');

    const renderOne = (r) => `
        <div class="config-item" style="display:flex;align-items:center;gap:10px;padding:8px 10px;border:1px solid var(--border);border-radius:var(--border-radius);margin-bottom:8px;font-size:12px">
            <span style="min-width:20px;color:var(--text-secondary)">${r.sort_order}</span>
            <span style="flex:1;word-break:break-all"><code>${escapeHtml(r.pattern)}</code> → <code>${escapeHtml(r.replacement) || '<删除>'}</code></span>
            <label style="display:flex;align-items:center;gap:4px;font-size:11px;white-space:nowrap">
                <input type="checkbox" ${r.enabled ? 'checked' : ''} onchange="toggleKeywordRule(${r.id}, this.checked)"> 启用
            </label>
            <button class="btn-sm" onclick="editKeywordRule(${r.id})">编辑</button>
            <button class="btn-sm danger" onclick="deleteKeywordRule(${r.id})">删除</button>
        </div>`;

    scanList.innerHTML = scanRules.length
        ? scanRules.map(renderOne).join('')
        : '<div class="empty-state" style="padding:12px;font-size:12px;color:var(--text-secondary)">暂无规则</div>';
    parseList.innerHTML = parseRules.length
        ? parseRules.map(renderOne).join('')
        : '<div class="empty-state" style="padding:12px;font-size:12px;color:var(--text-secondary)">暂无规则</div>';
}

async function addKeywordRule(scope) {
    const pattern = document.getElementById(scope + 'Pattern').value.trim();
    if (!pattern) {
        toast('请填写查找内容', 'warning');
        return;
    }
    const replacement = document.getElementById(scope + 'Replacement').value;
    const sortOrder = parseInt(document.getElementById(scope + 'Order').value) || 0;
    const enabled = document.getElementById(scope + 'Enabled').checked;
    try {
        await apiPost('/keyword-replaces', { scope, pattern, replacement, sort_order: sortOrder, enabled });
        document.getElementById(scope + 'Pattern').value = '';
        document.getElementById(scope + 'Replacement').value = '';
        toast('已添加规则', 'success');
        loadKeywordRules();
    } catch (e) {
        toast('添加失败: ' + (e.message || e), 'error');
    }
}

async function toggleKeywordRule(id, enabled) {
    try {
        const resp = await apiGet('/keyword-replaces');
        const rule = (resp.rules || []).find(r => r.id === id);
        if (!rule) return;
        await apiPut('/keyword-replaces/' + id, {
            scope: rule.scope, pattern: rule.pattern,
            replacement: rule.replacement, sort_order: rule.sort_order, enabled,
        });
        toast('已更新', 'success');
    } catch (e) {
        toast('更新失败: ' + (e.message || e), 'error');
        loadKeywordRules();
    }
}

async function deleteKeywordRule(id) {
    if (!confirm('确定删除该规则？')) return;
    try {
        await apiDelete('/keyword-replaces/' + id);
        toast('已删除', 'success');
        loadKeywordRules();
    } catch (e) {
        toast('删除失败: ' + (e.message || e), 'error');
    }
}

async function editKeywordRule(id) {
    try {
        const resp = await apiGet('/keyword-replaces');
        const rule = (resp.rules || []).find(r => r.id === id);
        if (!rule) return;
        const pattern = prompt('查找内容：', rule.pattern);
        if (pattern === null) return;
        const replacement = prompt('替换为（留空=删除）：', rule.replacement);
        if (replacement === null) return;
        const sortOrder = parseInt(prompt('顺序：', rule.sort_order)) || 0;
        await apiPut('/keyword-replaces/' + id, {
            scope: rule.scope, pattern: pattern.trim(),
            replacement, sort_order: sortOrder, enabled: rule.enabled,
        });
        toast('已保存', 'success');
        loadKeywordRules();
    } catch (e) {
        toast('保存失败: ' + (e.message || e), 'error');
    }
}

// ===================== 页面切换 =====================
function switchPageTab(tab) {
    document.querySelectorAll('.page-tab').forEach(el => el.classList.remove('active'));
    document.querySelectorAll('.page-content').forEach(el => el.style.display = 'none');
    document.getElementById('tab' + tab.charAt(0).toUpperCase() + tab.slice(1)).classList.add('active');
    document.getElementById('page' + tab.charAt(0).toUpperCase() + tab.slice(1)).style.display = '';
    if (tab === 'help') loadHelpDocs();
    if (tab === 'settings') { loadKeywordRules(); loadDupRuleConfigs(); }
    if (tab === 'pipeline') { loadPipelinePage(); startDebugLogPoll(); }
    else { stopDebugLogPoll(); }
    if (tab === 'logs') { switchLogView(logViewMode); startLogPagePoll(); }
    else { stopLogPagePoll(); }
}

// ===================== 初始化 =====================
async function init() {
    try {
        // 仅绑定一次表格事件委托（幂等，避免重复绑定导致监听器泄漏）
        attachTableDelegation();

        await Promise.all([
            loadConfigs(),
            loadColumnConfigs(),
            updateStats(true),
        ]);

        if (state.configs.length > 0 && !state.currentConfigId) {
            selectConfig(state.configs[0].id);
        }

        // 页面刷新后恢复正在执行的解析任务
        const savedTaskId = sessionStorage.getItem('parseTaskId');
        if (savedTaskId) {
            try {
                const info = await apiGet(`/parse-tasks/${savedTaskId}`);
                if (info.status === 'running') {
                    pollParseTask(savedTaskId);
                } else {
                    // 任务已完成，展示最终状态后自动关闭
                    pollParseTask(savedTaskId);
                }
            } catch {
                // 任务不存在（服务重启等），清除记录，再查一次running兜底
                sessionStorage.removeItem('parseTaskId');
                tryFallbackParseTask();
            }
        } else {
            // 没有保存的任务ID，查询后端是否有正在运行的任务（兜底）
            tryFallbackParseTask();
        }
    } catch (e) {
        toast('初始化加载失败，请确保后端服务已启动: ' + e.message, 'error');
    }
}

document.addEventListener('DOMContentLoaded', init);

// 兜底：查询后端是否有正在运行的解析任务
async function tryFallbackParseTask() {
    try {
        const info = await apiGet('/parse-tasks/running');
        if (info.task_id) {
            sessionStorage.setItem('parseTaskId', info.task_id);
            pollParseTask(info.task_id);
        }
    } catch {
        // 静默忽略
    }
}
