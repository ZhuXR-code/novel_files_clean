import Foundation
import StoreKit

/// 买断制（非消耗型）内购管理：一次付费，永久解锁全部功能。
/// 产品 ID 需在 App Store Connect 创建「非消耗型项目」，并与此处保持一致。
enum IAPManager {
    /// 与 App Store Connect 中创建的非消耗型项目 Product ID 完全一致。
    static let productID = "com.booksclean.app.unlock"

    /// 监听交易更新（购买/恢复后由系统回调）。
    /// 在 App 启动时调用一次即可。
    static func observeTransactions() {
        Task {
            for await verification in Transaction.updates {
                if case .verified(let tx) = verification {
                    // 买断制：只要存在已验证交易即视为永久解锁
                    await tx.finish()
                    await refreshUnlockedState()
                }
            }
        }
    }

    /// 向 App Store 查询当前是否已购买（恢复购买/启动时校验）。
    /// 返回 true 表示已解锁。
    @MainActor
    static func refreshUnlockedState() async -> Bool {
        do {
            for await verification in Transaction.currentEntitlements {
                if case .verified(let tx) = verification {
                    if tx.productID == productID, tx.revocationDate == nil {
                        Preferences.shared.unlocked = true
                        return true
                    }
                }
            }
        } catch {
            // 查询失败（如离线）时保留本地已存状态，不强制锁回。
        }
        // 本地已解锁则保持（首次离线也能用）。
        return Preferences.shared.unlocked
    }

    /// 拉取产品信息（用于显示价格）。
    static func loadProduct() async -> Product? {
        do {
            let products = try await Product.products(for: [productID])
            return products.first
        } catch {
            return nil
        }
    }

    /// 发起购买。成功返回 true。
    @MainActor
    static func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    Preferences.shared.unlocked = true
                    return true
                }
                return false
            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    /// 恢复购买：触发系统恢复流程并刷新状态。
    @MainActor
    static func restore() async -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            // 同步失败也尝试刷新本地已购状态
        }
        return await refreshUnlockedState()
    }
}
