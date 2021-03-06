//
//  UIViewController.swift
//  openposeTest5
//
//  Created by tpomac2017 on 2017/11/13.
//  Copyright © 2017年 tpomac2017. All rights reserved.
//

import Foundation

import UIKit
import Upsurge
import IteratorTools

extension CGPoint {
    init(_ x: CGFloat, _ y: CGFloat) {
        self.x = x
        self.y = y
    }
}
extension UIColor {
    class func rgb(_ r: Int,_ g: Int,_ b: Int) -> UIColor{
        return UIColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1)
    }
}
struct Connection {
    var score: Double
    var c1: (Int, Int)
    var c2: (Int, Int)
    var idx: (Int, Int)
    var partIdx: CGPoint
    var uPartIdx: Set<String>
    
    init(score: Double,c1: (Int, Int),c2: (Int, Int),idx: (Int, Int),partIdx: CGPoint,uPartIdx: Set<String>) {
        self.score = score
        self.c1 = c1
        self.c2 = c2
        self.idx = idx
        self.partIdx = partIdx
        self.uPartIdx = uPartIdx
    }
}

class Common {
    
    let opencv = OpenCVWrapper()
    
    var heatRows = 0
    var heatColumns = 0
    
    let cocoPairs = [
        CGPoint(1, 2),   CGPoint(1, 5),   CGPoint(2, 3),  CGPoint(3, 4),  CGPoint(5, 6),
        CGPoint(6, 7),   CGPoint(1, 8),   CGPoint(8, 9),  CGPoint(9, 10), CGPoint(1, 11),
        CGPoint(11, 12), CGPoint(12, 13), CGPoint(1, 0),  CGPoint(0, 14), CGPoint(14, 16),
        CGPoint(0, 15),  CGPoint(15, 17), CGPoint(2, 16), CGPoint(5, 17)
    ]
    
    let cocoPairsNetwork = [
        CGPoint(12, 13), CGPoint(20, 21), CGPoint(14, 15), CGPoint(16, 17), CGPoint(22, 23),
        CGPoint(24, 25), CGPoint(0, 1),   CGPoint(2, 3),   CGPoint(4, 5),   CGPoint(6, 7),
        CGPoint(8, 9),   CGPoint(10, 11), CGPoint(28, 29), CGPoint(30, 31), CGPoint(34, 35),
        CGPoint(32, 33), CGPoint(36, 37), CGPoint(18, 19), CGPoint(26, 27)
    ]
    
    let cocoColors = [UIColor.rgb(255, 0, 0),  UIColor.rgb(255, 85, 0), UIColor.rgb(255, 170, 0),UIColor.rgb(255, 255, 0),
                      UIColor.rgb(170, 255, 0),UIColor.rgb(85, 255, 0), UIColor.rgb(0, 255, 0),  UIColor.rgb(0, 255, 85),
                      UIColor.rgb(0, 255, 170),UIColor.rgb(0, 255, 255),UIColor.rgb(0, 170, 255),UIColor.rgb(0, 85, 255),
                      UIColor.rgb(0, 0, 255),  UIColor.rgb(85, 0, 255), UIColor.rgb(170, 0, 255),UIColor.rgb(255, 0, 255),
                      UIColor.rgb(255, 0, 170),UIColor.rgb(255, 0, 85)]
    
    let nmsThreshold = 0.05
    let interMinAboveThreshold = 4
    let interThreashold = 0.05
    let minSubsetCnt = 3
    let minSubsetScore = 0.4
//    let maxHuman = 96
    
    init(_ imageWidth: Int,_ imageHeight: Int){
        heatRows = imageWidth / 8
        heatColumns = imageHeight / 8
    }
    
    func estimatePose (_ mm: Array<Double>) -> [Int: [Connection]] {
        let startTime4 = CFAbsoluteTimeGetCurrent()
        
        let separateLen = 19*heatRows*heatColumns
        var heatMat = Matrix<Double>(rows: 19, columns: heatRows*heatColumns,
                                     elements: Array<Double>(mm[0..<separateLen]))
        let pafMat = Matrix<Double>(rows: 38, columns: heatRows*heatColumns,
                                    elements: Array<Double>(mm[separateLen..<mm.count]))
        
        heatMat = Matrix<Double>(
            (0..<heatMat.rows).map({ ValueArray<Double>(heatMat.row($0)) - min(heatMat.row($0)) }))
        
        // Separate every 2116 (46 x 46) and find the minimum value
        let q = ValueArray<Double>(capacity: heatMat.elements.count)
        for i in 0..<heatMat.rows {
            let a = Matrix<Double>(rows: heatRows, columns: heatColumns, elements: ValueArray<Double>(heatMat.row(i)))
            q.append(contentsOf:
                ((0..<a.rows).map{ ValueArray<Double>(a.row($0)) - min(a.row($0)) }).joined()
            )
        }
        heatMat = q.toMatrix(rows: 19, columns: heatRows*heatColumns)
        
        let timeElapsed4 = CFAbsoluteTimeGetCurrent() - startTime4
        print("init elapsed for \(timeElapsed4) seconds")
        
        let startTime3 = CFAbsoluteTimeGetCurrent()
        
//        print(sum(heatMat.elements)) // 810.501374994155
        var _NMS_Threshold = max(mean(heatMat.elements) * 4.0, nmsThreshold)
        _NMS_Threshold = min(_NMS_Threshold, 0.3)
        print(_NMS_Threshold) // 0.0806388792154168
        var coords = [[[Int]]]()
        
//        print("============")
//        print(heatMat.elements.count) // 40204
//        print(heatMat.columns) // 2116
//        print(heatMat.rows) // 19
//        print(_NMS_Threshold)
        for i in 0..<heatMat.rows-1 {
            var nms = Array<Double>(heatMat.row(i))
            nonMaxSuppression(&nms, dataRows: Int32(heatColumns),
                              maskSize: 5, threshold: _NMS_Threshold)
            let c = nms.enumerated().filter{ $0.1 > _NMS_Threshold }.map { x in
                return  [ Int(x.0 / heatRows) , Int(x.0 % heatRows) ]
            }
            coords.append(c)
        }
        
        // result heatMat parts
//        let startTime2 = CFAbsoluteTimeGetCurrent()
        
        var conn = [Connection]()
        for (idx, paf) in zip(cocoPairs, cocoPairsNetwork) {
            let idx1 = Int(idx.x)
            let idx2 = Int(idx.y)
            let pafXIdx = Int(paf.x)
            let pafYIdx = Int(paf.y)
            
            let pafMatX = ValueArray<Double>(pafMat.row(pafXIdx))
            let pafMatY = ValueArray<Double>(pafMat.row(pafYIdx))
            
            let connection = estimatePosePair(coords, idx1, idx2, pafMatX, pafMatY)
            conn.append(contentsOf: connection)
        }
        
//        let timeElapsed2 = CFAbsoluteTimeGetCurrent() - startTime2
//        print("estimate_pose_pair: elapsed for \(timeElapsed2) seconds")
        
        var connectionByHuman = [Int: [Connection]]()
        for (idx, c) in conn.enumerated(){
            connectionByHuman[idx] = [Connection]()
            connectionByHuman[idx]!.append(c)
        }
        
        var connectionIndexTmp = conn.indices.map {$0}
        
        var noMergeCache = [Int: [Int]]()
        for idx in conn.indices {
            noMergeCache[idx] = []
        }
        
        let timeElapsed3 = CFAbsoluteTimeGetCurrent() - startTime3
        print("others elapsed for \(timeElapsed3) seconds")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        while true {
            var is_merged = false
            
            for idx in connectionIndexTmp.combinations(length: 2){
                let k1 = idx[0]
                let k2 = idx[1]
                
//                print(String(format: "%d - %d",k1 ,k2))
                if k1 == k2{
                    continue
                }
                if noMergeCache[k1]!.contains(k2) {
                    continue
                }
                
                for prd in product(connectionByHuman[k1]!,connectionByHuman[k2]!){
                    
                    if prd[0].uPartIdx.intersection(prd[1].uPartIdx).count > 0 {
                        if let num = connectionIndexTmp.index(of: k2) {
                            is_merged = true
                            connectionByHuman[k1]!.append(contentsOf: connectionByHuman[k2]!)
                            connectionByHuman.removeValue(forKey: k2)
                            connectionIndexTmp.remove(at: num)
                            break;
                        }
                    }
                }
                if is_merged {
                    noMergeCache[k1] = []
                    break
                } else {
                    noMergeCache[k1]!.append(k2)
                }
            }
            
            if !is_merged {
                break
            }
        }
        
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("human_roop Time elapsed for roop: \(timeElapsed) seconds")
        
        // Unimplemented processing
        
        //  connection_by_human = {k: v for (k, v) in connection_by_human.items() if len(v) >= Min_Subset_Cnt}
        //  # reject by subset max score
        //  connection_by_human = {k: v for (k, v) in connection_by_human.items() if max([ii['score'] for ii in v]) >= Min_Subset_Score}
        
//        print(connectionByHuman[0])
        return connectionByHuman
        
    }
    
    func nonMaxSuppression(_ data: inout [Double],
                           dataRows: Int32,
                           maskSize: Int32,
                           threshold: Double) {
        
        opencv.maximum_filter(
            &data,
            data_size: Int32(data.count),
            data_rows: dataRows,
            mask_size: maskSize,
            threshold: threshold
        )
    }
    
    func getScore(_ x1 : Int,_ y1: Int,_ x2: Int,_ y2: Int,_ pafMatX: ValueArray<Double>,_ pafMatY: ValueArray<Double>) -> (Double,Int) {
        let __numInter = 10
        let __numInterF = Double(__numInter)
        let dx = Double(x2 - x1)
        let dy = Double(y2 - y1)
        let normVec = sqrt(pow(dx,2) + pow(dy,2))
        
        if normVec < 1e-4 {
            return (0.0, 0)
        }
        let vx = dx / normVec
        let vy = dy / normVec
        var xs : [Double]
        
        if x1 == x2 {
            xs = Array<Double>(repeating: Double(x1) , count: __numInter)
        } else {
            xs = stride(from: Double(x1), to: Double(x2), by: Double(dx / __numInterF)).map {$0}
        }
        var ys : [Double]
        if y1 == y2 {
            ys = Array<Double>(repeating: Double(y1) , count: __numInter)
        } else {
            ys = stride(from: Double(y1), to: Double(y2), by: Double(dy / __numInterF)).map {$0}
        }
        let xs2 = xs.map{ Int($0+0.5) }
        let ys2 = ys.map{ Int($0+0.5) }
        
        var pafXs : [Double] = Array(repeating: 0.0 , count: __numInter)
        var pafYs : [Double] = Array(repeating: 0.0 , count: __numInter)
        for (idx, (mx, my)) in zip(xs2, ys2).enumerated(){
            pafXs[idx] = pafMatX[my*heatRows+mx]
            pafYs[idx] = pafMatY[my*heatRows+mx]
        }
        
        let localScores = pafXs * vx + pafYs * vy
        
        var res = localScores.filter({$0 > interThreashold})
        if (res.count > 0){
            res[0] = 0.0
        }
        return (sum(res), res.count)
    }
    func estimatePosePair(_ coords : [[[Int]]] ,
                            _ partIdx1: Int,_ partIdx2: Int,
                            _ pafMatX: ValueArray<Double>, _ pafMatY: ValueArray<Double>) -> [Connection] {
        
        let peakCoord1 = coords[partIdx1]
        let peakCoord2 = coords[partIdx2]
        
        var connection = [Connection]()
        var cnt = 0
        for (idx1, x) in peakCoord1.enumerated() {
            let x1 = x[1]
            let y1 = x[0]
            for (idx2, xx) in peakCoord2.enumerated() {
                let x2 = xx[1]
                let y2 = xx[0]
                let (score, count) = getScore(x1, y1, x2, y2, pafMatX, pafMatY)
                cnt += 1
                if count < interMinAboveThreshold || score <= 0.0 {
                    continue
                }
                
                connection.append(Connection(
                    score: score,
                    c1: (x1, y1),
                    c2: (x2, y2),
                    idx: (idx1, idx2),
                    partIdx: CGPoint(x: partIdx1,y: partIdx2),
                    uPartIdx: Set<String>([String(format: "%d-%d-%d", x1, y1, partIdx1) , String(format: "%d-%d-%d", x2, y2, partIdx2)])
                ))
            }
        }
        
        // Multiple score cuts
        var connectionTmp = [Connection]()
        var used_idx1 = [Int]()
        var used_idx2 = [Int]()
        connection.sorted{ $0.score > $1.score }.forEach { conn in
            
            if used_idx1.contains(conn.idx.0) || used_idx2.contains(conn.idx.1) {
                return
            }
            connectionTmp.append(conn)
            used_idx1.append(conn.idx.0)
            used_idx2.append(conn.idx.1)
        }
        
        return connectionTmp
    }
}

