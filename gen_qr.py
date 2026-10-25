import qrcode
scanurl = 'https://open.weixin.qq.com/connect/confirm?uuid=021bFpFo4vi1ll2F'
img = qrcode.make(scanurl)
out = r'D:\Develop\TrendRadar\wewe-login-qr.png'
img.save(out)
print('QR saved:', out)
