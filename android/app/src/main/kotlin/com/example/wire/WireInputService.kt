package com.example.wire

import android.accessibilityservice.AccessibilityService
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class WireInputService : AccessibilityService() {
    companion object {
        @Volatile
        var instance: WireInputService? = null
            private set
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No-op: used for input injection only.
    }

    override fun onInterrupt() {
        // No-op
    }

    fun inputText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: findEditableNode(root) ?: return false
        val args = Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun findEditableNode(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (root.isEditable) return root
        for (i in 0 until root.childCount) {
            val child = root.getChild(i) ?: continue
            val found = findEditableNode(child)
            if (found != null) return found
        }
        return null
    }
}
