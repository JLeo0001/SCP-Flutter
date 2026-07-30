// SCP-Flutter 阅读 JS 模板 — 构建时存入 offline_content.db
// 动态设置（字号、行高等）由 Flutter 端通过 evaluateJavascript 注入

// 进度条
(function(){
    var bar = document.createElement('div');
    bar.id = 'reading-progress';
    document.body.appendChild(bar);
    function update() {
        var scrollTop = window.scrollY || document.documentElement.scrollTop || 0;
        var docHeight = Math.max(
            document.body.scrollHeight, document.documentElement.scrollHeight,
            document.body.offsetHeight, document.documentElement.offsetHeight
        ) - window.innerHeight;
        var pct = docHeight > 0 ? Math.min(scrollTop / docHeight * 100, 100) : 0;
        bar.style.width = pct + '%';
    }
    window.addEventListener('scroll', update, {passive: true});
    window.addEventListener('resize', update, {passive: true});
    update();
})();

// 脚注弹窗
(function(){
    document.addEventListener('click', function(e) {
        var target = e.target.closest('a');
        if (!target || !target.hash) return;
        var fn = document.querySelector(target.hash);
        if (!fn || !fn.classList.contains('footnote')) return;
        e.preventDefault();
        var existing = document.querySelector('.fn-popup');
        if (existing) existing.remove();
        var popup = document.createElement('div');
        popup.className = 'fn-popup';
        popup.innerHTML = fn.innerHTML;
        popup.style.cssText = 'position:fixed;background:#333;color:#fff;padding:12px 16px;' +
            'border-radius:8px;font-size:14px;line-height:1.5;max-width:80%;' +
            'z-index:9998;box-shadow:0 4px 12px rgba(0,0,0,0.3);';
        var rect = target.getBoundingClientRect();
        var top = rect.top - popup.offsetHeight - 8;
        if (top < 8) top = rect.bottom + 8;
        popup.style.top = top + 'px';
        popup.style.left = Math.max(8, Math.min(rect.left, window.innerWidth - popup.offsetWidth - 8)) + 'px';
        document.body.appendChild(popup);
        document.addEventListener('click', function dismiss(e2) {
            if (!e2.target.closest('.fn-popup')) {
                popup.remove();
                document.removeEventListener('click', dismiss);
            }
        }, {once: true});
    });
})();

// 代码块复制按钮
(function(){
    document.querySelectorAll('pre').forEach(function(pre) {
        var btn = document.createElement('button');
        btn.textContent = '复制';
        btn.style.cssText = 'float:right;font-size:12px;padding:2px 8px;' +
            'border:1px solid #ddd;border-radius:4px;background:#fff;cursor:pointer;';
        btn.addEventListener('click', function() {
            var code = pre.querySelector('code');
            var text = code ? code.textContent : pre.textContent;
            if (navigator.clipboard) {
                navigator.clipboard.writeText(text).then(function() {
                    btn.textContent = '✓';
                    setTimeout(function(){ btn.textContent = '复制'; }, 1500);
                });
            }
        });
        pre.style.position = 'relative';
        pre.insertBefore(btn, pre.firstChild);
    });
})();

// 折叠块交互
(function(){
    document.querySelectorAll('.collapsible-block').forEach(function(block) {
        var title = block.querySelector('.collapsible-block-title');
        var content = block.querySelector('.collapsible-block-content');
        if (title && content) {
            title.style.cursor = 'pointer';
            title.addEventListener('click', function() {
                var isHidden = content.style.display === 'none';
                content.style.display = isHidden ? '' : 'none';
            });
        }
    });
})();
