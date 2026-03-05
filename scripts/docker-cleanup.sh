#!/bin/bash

# Docker 清理脚本
# 用于清理本项目相关的 Docker 镜像、容器和缓存

set -e

COLOR_RESET='\033[0m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'

echo -e "${COLOR_BLUE}╔════════════════════════════════════════╗${COLOR_RESET}"
echo -e "${COLOR_BLUE}║   Traffic Replayer - Docker 清理工具   ║${COLOR_RESET}"
echo -e "${COLOR_BLUE}╚════════════════════════════════════════╝${COLOR_RESET}"
echo ""

# 显示当前 Docker 使用情况
echo -e "${COLOR_YELLOW}📊 当前 Docker 使用情况:${COLOR_RESET}"
docker system df
echo ""

# 询问清理范围
echo -e "${COLOR_YELLOW}请选择清理范围:${COLOR_RESET}"
echo "  1) 仅清理项目相关镜像和容器"
echo "  2) 清理所有未使用的 Docker 资源 (推荐)"
echo "  3) 完全清理 (包括构建缓存)"
echo "  4) 取消"
echo ""
read -p "请输入选项 [1-4]: " choice

case $choice in
    1)
        echo -e "\n${COLOR_GREEN}🧹 清理项目相关资源...${COLOR_RESET}"
        
        # 停止并删除相关容器
        echo "📦 停止并删除容器..."
        docker ps -a --filter "name=replayer" --format "{{.ID}}" | xargs -r docker rm -f || true
        
        # 删除项目镜像
        echo "🖼️  删除项目镜像..."
        docker images --filter "reference=traffic-replayer*" --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi -f || true
        
        echo -e "${COLOR_GREEN}✓ 项目资源清理完成${COLOR_RESET}"
        ;;
    
    2)
        echo -e "\n${COLOR_GREEN}🧹 清理未使用的 Docker 资源...${COLOR_RESET}"
        
        # 清理停止的容器
        echo "📦 清理停止的容器..."
        docker container prune -f
        
        # 清理悬空镜像
        echo "🖼️  清理悬空镜像..."
        docker image prune -f
        
        # 清理未使用的网络
        echo "🌐 清理未使用的网络..."
        docker network prune -f
        
        # 清理未使用的卷
        echo "💾 清理未使用的卷..."
        docker volume prune -f
        
        echo -e "${COLOR_GREEN}✓ 未使用资源清理完成${COLOR_RESET}"
        ;;
    
    3)
        echo -e "\n${COLOR_RED}⚠️  完全清理将删除所有构建缓存，下次构建会更慢！${COLOR_RESET}"
        read -p "确认继续? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "\n${COLOR_GREEN}🧹 完全清理所有资源...${COLOR_RESET}"
            
            # 停止所有容器
            echo "📦 停止所有容器..."
            docker ps -q | xargs -r docker stop || true
            
            # 系统清理
            docker system prune -af --volumes
            
            echo -e "${COLOR_GREEN}✓ 完全清理完成${COLOR_RESET}"
        else
            echo "已取消"
            exit 0
        fi
        ;;
    
    4)
        echo "已取消"
        exit 0
        ;;
    
    *)
        echo -e "${COLOR_RED}❌ 无效选项${COLOR_RESET}"
        exit 1
        ;;
esac

echo ""
echo -e "${COLOR_YELLOW}📊 清理后 Docker 使用情况:${COLOR_RESET}"
docker system df
echo ""
echo -e "${COLOR_GREEN}✨ 清理完成！${COLOR_RESET}"
