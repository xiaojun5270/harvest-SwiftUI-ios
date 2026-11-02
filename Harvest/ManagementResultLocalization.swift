import Foundation

/// Localize presentation labels and machine states while preserving source values.
enum ManagementResultLocalization {
    private static let common: [String: String] = [
        "id": "编号", "name": "名称", "title": "标题", "text": "内容",
        "message": "返回信息", "msg": "返回信息", "description": "说明", "summary": "状态概览",
        "status": "状态", "state": "状态", "level": "级别", "code": "状态代码",
        "type": "类型", "category": "分类", "role": "消息角色", "enabled": "是否启用",
        "available": "是否可用", "active": "是否活跃", "online": "是否在线",
        "is_enabled": "是否启用", "is_active": "是否活跃", "is_online": "是否在线",
        "is_available": "是否可用", "success": "是否成功", "succeed": "是否成功",
        "error": "错误信息", "error_message": "错误信息", "reason": "原因", "detail": "详细信息",
        "details": "详细信息", "result": "执行结果", "results": "执行结果", "data": "数据",
        "items": "条目", "records": "记录", "list": "列表", "count": "数量", "total": "总数",
        "total_count": "总数", "created": "新增数量", "updated": "更新数量", "item_count": "条目数",
        "created_at": "创建时间", "updated_at": "更新时间", "generated_at": "生成时间",
        "collected_at": "采集时间", "timestamp": "记录时间", "time": "时间", "date": "日期", "day": "日期"
    ]

    private static let groups: [String: String] = [
        "context": "本次项目状态", "snapshot": "状态快照", "project": "项目", "overview": "总体概况",
        "stats": "统计", "statistics": "统计", "totals": "汇总", "counts": "数量统计",
        "sites": "站点", "site": "站点", "site_list": "站点列表", "site_stats": "站点统计",
        "site_summary": "站点概况", "site_id": "站点编号", "site_name": "站点名称",
        "sites_total": "站点总数", "sites_enabled": "已启用站点", "sites_disabled": "已停用站点",
        "downloaders": "下载器", "downloader": "下载器", "downloader_list": "下载器列表",
        "downloader_stats": "下载器统计", "downloader_summary": "下载器概况",
        "downloader_id": "下载器编号", "downloader_name": "下载器名称",
        "downloaders_total": "下载器总数", "downloaders_active": "活跃下载器",
        "downloaders_online": "在线下载器", "downloaders_offline": "离线下载器",
        "tasks": "任务", "task": "任务", "schedules": "计划任务", "schedule_tasks": "计划任务数量",
        "scheduled_tasks": "计划任务", "schedule_list": "计划任务列表", "task_id": "任务编号",
        "task_name": "任务名称", "recent_results": "近期执行记录", "recent_task_results": "近期任务结果",
        "rss": "订阅", "rss_feeds": "订阅源", "rss_subscriptions": "订阅数量",
        "feeds": "订阅源", "subscriptions": "订阅", "plans": "订阅方案", "history": "历史记录",
        "findings": "诊断结果", "warnings": "警告", "errors": "错误", "recommendations": "处理建议",
        "health": "健康状态", "config": "配置", "settings": "设置", "server": "服务器"
    ]

    private static let metrics: [String: String] = [
        "model": "模型", "provider": "服务类型", "prompt_tokens": "输入 Token",
        "completion_tokens": "输出 Token", "daily_limit": "每日额度", "total_tokens": "Token 总用量",
        "feed_name": "订阅源名称", "feed_id": "订阅源编号", "subscription_id": "订阅编号",
        "subscription_name": "订阅名称", "pushed": "是否已推送", "last_build": "最近构建时间",
        "published_at": "发布时间", "size": "大小（字节）", "link": "详情链接", "url": "访问地址",
        "host": "主机地址", "port": "端口", "username": "用户名", "email": "邮箱",
        "author": "作者", "is_read": "是否已读", "connection_status": "连接状态",
        "version": "版本", "client": "客户端", "protocol": "连接协议", "upload_speed": "上传速度",
        "download_speed": "下载速度", "uploaded": "累计上传", "downloaded": "累计下载",
        "uploaded_total": "上传总量", "downloaded_total": "下载总量", "seeding": "做种数量",
        "leeching": "下载中数量", "seed_volume": "做种体积", "ratio": "分享率",
        "bonus": "魔力值", "score": "积分", "level_name": "用户等级", "user_level": "用户等级",
        "sign_in": "签到", "sign_status": "签到状态", "signed_in": "是否已签到",
        "last_sign_in": "最近签到时间", "last_sign_time": "最近签到时间", "last_active": "最近活跃时间",
        "last_run": "最近执行时间", "next_run": "下次执行时间", "last_run_at": "最近执行时间",
        "next_run_at": "下次执行时间", "duration": "耗时", "duration_seconds": "耗时（秒）",
        "active_torrent_count": "活跃种子数", "paused_torrent_count": "暂停种子数", "torrent_count": "种子总数"
    ]

    private static let words: [String: String] = [
        "site": "站点", "sites": "站点", "downloader": "下载器", "downloaders": "下载器",
        "schedule": "计划", "scheduled": "计划", "schedules": "计划任务", "task": "任务", "tasks": "任务",
        "rss": "订阅", "feed": "源", "feeds": "源", "subscription": "订阅", "subscriptions": "订阅",
        "total": "总数", "count": "数量", "enabled": "已启用", "disabled": "已停用", "active": "活跃",
        "online": "在线", "offline": "离线", "success": "成功", "failed": "失败", "failure": "失败",
        "warning": "警告", "error": "错误", "recent": "近期", "last": "最近", "next": "下次",
        "result": "结果", "results": "结果", "record": "记录", "records": "记录", "list": "列表",
        "name": "名称", "id": "编号", "summary": "概况", "stats": "统计", "status": "状态",
        "history": "历史", "run": "执行", "time": "时间", "date": "日期", "at": "时间",
        "upload": "上传", "download": "下载", "speed": "速度", "bytes": "字节", "size": "大小",
        "torrent": "种子", "torrents": "种子", "paused": "暂停", "connected": "已连接", "disconnected": "未连接"
    ]

    private static let states: [String: String] = [
        "success": "成功", "successful": "成功", "succeeded": "成功", "ok": "正常", "healthy": "正常",
        "normal": "正常", "warning": "警告", "warn": "警告", "error": "错误", "failed": "失败",
        "failure": "失败", "critical": "严重", "info": "提示", "debug": "调试", "enabled": "已启用",
        "disabled": "已停用", "active": "活跃", "inactive": "未活跃", "online": "在线", "offline": "离线",
        "connected": "已连接", "disconnected": "未连接", "running": "执行中", "pending": "待执行",
        "queued": "排队中", "waiting": "等待中", "paused": "已暂停", "stopped": "已停止", "done": "已完成",
        "completed": "已完成", "cancelled": "已取消", "canceled": "已取消", "timeout": "超时",
        "unknown": "未知", "unavailable": "不可用", "available": "可用", "skipped": "已跳过",
        "signed": "已签到", "signed_in": "已签到", "not_signed": "未签到", "not_signed_in": "未签到",
        "user": "用户", "assistant": "AI 助手", "system": "系统", "true": "是", "false": "否"
    ]

    static func fieldTitle(_ key: String) -> String {
        let normalized = normalizedKey(key)
        for labels in [common, groups, metrics] {
            if let title = labels[normalized] { return title }
        }
        if key.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains(Int($0.value)) }) { return key }
        let parts = normalized.split(separator: "_").map(String.init)
        let translated = parts.compactMap { words[$0] }
        if !parts.isEmpty, translated.count == parts.count { return translated.joined() }
        return "其他信息"
    }

    static func displayValue(_ value: String, for key: String) -> String {
        let normalized = normalizedKey(key)
        let stateKeys: Set<String> = [
            "status", "state", "level", "role", "connection_status", "sign_status", "health",
            "enabled", "disabled", "available", "active", "online", "is_enabled", "is_active", "is_online",
            "is_available", "success", "succeed", "pushed", "signed_in", "sign_in", "is_read"
        ]
        guard stateKeys.contains(normalized) else { return value }
        return states[normalizedKey(value)] ?? value
    }

    private static func normalizedKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "([A-Z]+)([A-Z][a-z])", with: "$1_$2", options: .regularExpression)
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1_$2", options: .regularExpression)
            .replacingOccurrences(of: "[- .]+", with: "_", options: .regularExpression)
            .lowercased()
    }
}
