import Foundation

enum DemoJSON {
    static let text = """
    {
      "app": "QJson",
      "version": "0.1.0",
      "description": "面向查看与临时编辑的 JSON 工具，编辑结果可一键复制。",
      "theme": {
        "followSystem": true,
        "palettes": ["light", "dark"],
        "accent": "#0A84FF"
      },
      "features": [
        {
          "name": "语法高亮",
          "enabled": true,
          "scope": "visible"
        },
        {
          "name": "树形预览",
          "enabled": true,
          "scope": "virtualized"
        },
        {
          "name": "搜索",
          "enabled": true,
          "modes": ["keys", "values", "both"]
        }
      ],
      "limits": {
        "openSizeMB": 10,
        "maxDepth": 512,
        "debounceMs": 300
      },
      "sample": {
        "string": "含转义与中文：\\"引号\\"、换行\\n、制表符\\t",
        "unicode": "\\u4E2D\\u6587",
        "integer": 42,
        "float": -3.14159e+2,
        "bool": false,
        "nothing": null,
        "emptyObject": {},
        "emptyArray": []
      },
      "contacts": [
        { "name": "张三", "role": "管理员", "active": true },
        { "name": "李四", "role": "编辑", "active": false }
      ]
    }
    """
}
